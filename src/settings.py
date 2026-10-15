import json
from pathlib import Path
from urllib.parse import urlsplit

SETTINGS_PATH = Path.home() / '.config/codex-switcher/settings.json'
DEFAULTS = {
    'keychain_service': 'com.example.codex-switcher.gateway',
    'state_dir': str(Path.home() / 'Library/Application Support/codex-switcher'),
    'config_path': str(Path.home() / '.codex/config.toml'),
}


def load_settings():
    settings = dict(DEFAULTS)
    if SETTINGS_PATH.exists():
        try:
            custom = json.loads(SETTINGS_PATH.read_text(encoding='utf-8'))
        except (ValueError, OSError):
            raise ValueError('无法读取本机 settings.json，请检查文件格式和权限。') from None
        if not isinstance(custom, dict) or any(not isinstance(value, str) for value in custom.values()):
            raise ValueError('settings.json 必须是字符串键值组成的 JSON 对象。')
        settings.update(custom)
    return settings


def gateway_url(settings):
    value = settings.get('gateway_url', '').rstrip('/')
    parsed = urlsplit(value)
    if (parsed.scheme not in ('http', 'https') or not parsed.hostname
            or parsed.username or parsed.password or parsed.query or parsed.fragment
            or parsed.hostname == 'gateway.example.com'):
        raise ValueError('请先在本机 settings.json 中填写有效的 gateway_url。')
    return value
