import datetime
from pathlib import Path
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'src'))
from switcher import Manager, PROVIDER, tomlkit
from settings import gateway_url


class SwitcherTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.config = self.root / 'config.toml'
        self.source = '''# 保留个人配置注释
model = "gpt-example"
model_reasoning_effort = "medium"
[desktop]
codeFontSize = 13
[mcp_servers.demo]
url = "http://127.0.0.1:8788/mcp"
[plugins.demo]
enabled = true
'''
        self.config.write_text(self.source)
        self.manager = Manager(self.config, self.root / 'state', settings={
            'gateway_url': 'https://gateway.test/v1',
            'keychain_service': 'com.example.test'})
        self.manager.write_json('models.json', {
            'time': datetime.datetime.now().timestamp(),
            'models': [{'id': 'company-example', 'effort': 'medium'}]})

    def test_roundtrip_preserves_settings_comments_and_backup(self):
        self.manager.apply('company', 'company-example')
        company = tomlkit.parse(self.config.read_text())
        self.assertEqual(company['model_provider'], PROVIDER)
        provider = company['model_providers'][PROVIDER]
        self.assertEqual(provider['auth']['command'], '/usr/bin/security')
        self.assertNotIn('env_key', provider)
        self.assertNotIn('requires_openai_auth', provider)
        self.assertIn('# 保留个人配置注释', self.config.read_text())
        self.manager.apply('personal')
        self.assertEqual(tomlkit.parse(self.config.read_text()).unwrap(), tomlkit.parse(self.source).unwrap())
        for backup in (self.root / 'state/backups').glob('*.toml'):
            self.assertEqual(backup.stat().st_mode & 0o777, 0o600)
        self.assertEqual(self.config.stat().st_mode & 0o777, 0o600)

    def test_unknown_or_expired_model_leaves_config_unchanged(self):
        with self.assertRaises(ValueError):
            self.manager.apply('company', 'unknown')
        self.assertEqual(self.config.read_text(), self.source)
        self.manager.write_json('models.json', {'time': 0, 'models': [{'id': 'company-example'}]})
        with self.assertRaises(ValueError):
            self.manager.apply('company', 'company-example')
        self.assertEqual(self.config.read_text(), self.source)

    def test_snapshot_tracks_new_personal_model(self):
        self.manager.apply('company', 'company-example')
        self.manager.apply('personal')
        self.config.write_text(self.config.read_text().replace('gpt-example', 'personal-example'))
        self.manager.apply('company', 'company-example')
        self.manager.apply('personal')
        self.assertEqual(tomlkit.parse(self.config.read_text())['model'], 'personal-example')

    def test_custom_provider_is_not_overwritten(self):
        document = tomlkit.parse(self.source)
        document['model_provider'] = 'custom'
        custom = tomlkit.dumps(document)
        self.config.write_text(custom)
        with self.assertRaises(ValueError):
            self.manager.apply('company', 'company-example')
        self.assertEqual(self.config.read_text(), custom)

    def test_placeholder_or_missing_gateway_does_not_write_config(self):
        for value in ['', 'https://gateway.example.com/v1', 'https://user:secret@gateway.test/v1']:
            self.manager.settings['gateway_url'] = value
            with self.assertRaises(ValueError):
                self.manager.apply('company', 'company-example')
            self.assertEqual(self.config.read_text(), self.source)

    def test_gateway_url_normalization(self):
        self.assertEqual(gateway_url({'gateway_url': 'https://gateway.test/v1/'}), 'https://gateway.test/v1')


if __name__ == '__main__':
    unittest.main()

