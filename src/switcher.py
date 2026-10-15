#!/usr/bin/python3
import argparse
import datetime
import fcntl
import getpass
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent / 'vendor'))
import tomlkit
from settings import load_settings, gateway_url

PROVIDER = 'company_gateway'
ROUTING_KEYS = ('model', 'model_provider', 'model_reasoning_effort',
                'model_catalog_json', 'model_catalog_url', 'web_search',
                'openai_base_url', 'chatgpt_base_url')


def atomic_write(path, text):
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix='.' + path.name, dir=str(path.parent))
    try:
        with os.fdopen(fd, 'w', encoding='utf-8') as stream:
            stream.write(text)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temporary, 0o600)
        os.replace(temporary, str(path))
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def read_token(settings):
    result = subprocess.run(['/usr/bin/security', 'find-generic-password', '-a',
                             getpass.getuser(), '-s', settings['keychain_service'], '-w'],
                            capture_output=True, text=True, timeout=30)
    if result.returncode or not result.stdout.strip():
        raise ValueError('无法读取公司 Token，请解锁系统钥匙串后重试。')
    return result.stdout.strip()


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, message, headers, newurl):
        return None


def fetch_models(settings):
    base_url = gateway_url(settings)
    token = read_token(settings)
    request = urllib.request.Request(base_url + '/models', headers={
        'Authorization': 'Bearer ' + token, 'Accept': 'application/json'})
    try:
        with urllib.request.build_opener(NoRedirect).open(request, timeout=15) as response:
            payload = json.load(response)
    except urllib.error.HTTPError as error:
        raise ValueError('公司模型目录返回 HTTP ' + str(error.code) + '，请检查网络、Token 和权限。') from None
    except (urllib.error.URLError, TimeoutError, OSError):
        raise ValueError('无法连接公司模型目录，请检查公司网络或 VPN。') from None
    if not isinstance(payload, dict) or not isinstance(payload.get('data'), list):
        raise ValueError('模型目录格式不正确。')
    models = []
    seen = set()
    for item in payload['data']:
        if not isinstance(item, dict):
            continue
        model = item.get('id')
        if not isinstance(model, str) or not re.fullmatch(r'[\x21-\x7e]{1,200}', model) or model in seen:
            continue
        seen.add(model)
        effort = item.get('reasoning_effort', {})
        effort = effort.get('defaultValue') if isinstance(effort, dict) else None
        models.append({'id': model, 'effort': effort if effort in
                       ('none', 'minimal', 'low', 'medium', 'high', 'xhigh', 'max') else None})
    if not models:
        raise ValueError('公司网关没有返回模型。')
    return models


class Manager:
    def __init__(self, config=None, state=None, settings=None):
        self.settings = load_settings() if settings is None else settings
        self.config = config or Path(self.settings['config_path']).expanduser()
        self.state = state or Path(self.settings['state_dir']).expanduser()

    def read(self):
        return self.config.read_text(encoding='utf-8')

    def read_json(self, name, default=None):
        path = self.state / name
        return json.loads(path.read_text(encoding='utf-8')) if path.exists() else default

    def write_json(self, name, value):
        atomic_write(self.state / name, json.dumps(value, ensure_ascii=False, indent=2) + '\n')

    def status(self):
        document = tomlkit.parse(self.read())
        provider = document.get('model_provider', 'openai')
        label = '公司模式' if provider == PROVIDER else '个人模式' if provider == 'openai' else '自定义网关：' + str(provider)
        return label + '；模型：' + str(document.get('model', '默认模型'))

    def details(self):
        document = tomlkit.parse(self.read())
        provider = str(document.get('model_provider', 'openai'))
        return {'mode': 'company' if provider == PROVIDER else 'personal' if provider == 'openai' else 'custom',
                'model': str(document.get('model', '默认模型')), 'provider': provider}

    def list_models(self):
        models = fetch_models(self.settings)
        previous = self.read_json('company-model.json', {}).get('model', '')
        models.sort(key=lambda model: model['id'] != previous)
        self.write_json('models.json', {'time': datetime.datetime.now().timestamp(), 'models': models})
        return models

    def transform(self, source, mode, snapshot, model=None, effort=None):
        document = tomlkit.parse(source)
        for key in ROUTING_KEYS:
            document.pop(key, None)
        if mode == 'personal':
            if not snapshot:
                raise ValueError('尚无个人配置快照，不能自动恢复个人模式。')
            for key, value in snapshot['routing'].items():
                document[key] = value
            providers = document.get('model_providers')
            if providers and PROVIDER in providers:
                del providers[PROVIDER]
                if not providers:
                    del document['model_providers']
        else:
            document['model_provider'] = PROVIDER
            document['model'] = model
            document['web_search'] = 'disabled'
            if effort:
                document['model_reasoning_effort'] = effort
            if 'model_providers' not in document:
                document['model_providers'] = tomlkit.table()
            provider = tomlkit.table()
            provider['name'] = 'Company Gateway Desktop'
            provider['base_url'] = gateway_url(self.settings)
            provider['wire_api'] = 'responses'
            provider['request_max_retries'] = 4
            provider['stream_max_retries'] = 10
            authentication = tomlkit.table()
            authentication['command'] = '/usr/bin/security'
            authentication['args'] = ['find-generic-password', '-a', getpass.getuser(), '-s',
                                      self.settings['keychain_service'], '-w']
            authentication['timeout_ms'] = 30000
            authentication['refresh_interval_ms'] = 300000
            provider['auth'] = authentication
            document['model_providers'][PROVIDER] = provider
        output = tomlkit.dumps(document)
        parsed = tomlkit.parse(output)
        # 对比非路由字段，防止误改插件、MCP、hooks 或其他用户设置。
        def unrelated(doc):
            value = doc.unwrap()
            for key in ROUTING_KEYS:
                value.pop(key, None)
            providers = value.get('model_providers', {})
            providers.pop(PROVIDER, None)
            if not providers:
                value.pop('model_providers', None)
            return value
        if unrelated(tomlkit.parse(source)) != unrelated(parsed):
            raise ValueError('检测到无关设置发生变化，已取消修改。')
        return output

    def apply(self, mode, model=None):
        self.state.mkdir(mode=0o700, parents=True, exist_ok=True)
        os.chmod(self.state, 0o700)
        with (self.state / 'switch.lock').open('a') as lock:
            try:
                fcntl.flock(lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                raise ValueError('另一个切换操作正在进行，请稍后重试。') from None
            source = self.read()
            document = tomlkit.parse(source)
            current = document.get('model_provider', 'openai')
            snapshot = self.read_json('personal-routing.json')
            if current == 'openai':
                snapshot = {'routing': {key: document[key].unwrap() for key in ROUTING_KEYS if key in document}}
            elif current != PROVIDER:
                raise ValueError('当前是其他自定义网关，请先手动恢复个人配置后再使用切换器。')
            effort = None
            if mode == 'company':
                catalog = self.read_json('models.json', {})
                if datetime.datetime.now().timestamp() - catalog.get('time', 0) > 3600:
                    raise ValueError('模型列表已过期，请重新选择公司模式以刷新。')
                selected = next((entry for entry in catalog.get('models', []) if entry['id'] == model), None)
                if not selected:
                    raise ValueError('所选模型不在刚查询的公司目录中，请重新选择。')
                effort = selected.get('effort')
            output = self.transform(source, mode, snapshot, model, effort)
            if snapshot:
                self.write_json('personal-routing.json', snapshot)
            stamp = datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f')
            atomic_write(self.state / 'backups' / ('config-' + stamp + '.toml'), source)
            # 检查备份期间是否有桌面进程或编辑器写入配置。
            if self.read() != source:
                raise ValueError('配置刚被其他程序修改，请重新运行切换器。')
            if mode == 'company':
                self.write_json('company-model.json', {'model': model})
            atomic_write(self.config, output)
            return self.status()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['status', 'status-json', 'models', 'models-json', 'switch'])
    parser.add_argument('--mode', choices=['personal', 'company'])
    parser.add_argument('--model')
    args = parser.parse_args()
    manager = Manager()
    if args.action == 'status':
        print(manager.status())
    elif args.action == 'status-json':
        print(json.dumps(manager.details(), ensure_ascii=False))
    elif args.action == 'models-json':
        print(json.dumps(manager.list_models(), ensure_ascii=False))
    elif args.action == 'models':
        print('\n'.join(model['id'] for model in manager.list_models()))
    else:
        if not args.mode:
            raise ValueError('未选择切换模式。')
        print(manager.apply(args.mode, args.model))


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        # 不回显配置正文、凭据、命令输出或服务端返回正文。
        if isinstance(error, ValueError) and type(error).__module__ == 'builtins':
            print(str(error), file=sys.stderr)
        else:
            print('操作失败（' + type(error).__name__ + '），配置未通过完整切换验证，请重试或检查备份。', file=sys.stderr)
        sys.exit(1)
