import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
from external_reader import read_external
from configure import validate
from runtime import DEFAULTS, save_connection
from discovery import discover


class InstallationTests(unittest.TestCase):
    def test_external_read_uses_utf8_and_never_shell(self):
        completed = subprocess.CompletedProcess([], 0, json.dumps({'source': 'Календарь'}).encode('utf-8'), b'')
        with patch('external_reader.subprocess.run', return_value=completed) as run:
            self.assertEqual(read_external(['reader.exe', '--json'])['source'], 'Календарь')
            self.assertNotIn('shell', run.call_args.kwargs)
            self.assertEqual(run.call_args.kwargs['timeout'], 45)
        with self.assertRaises(ValueError):
            read_external('reader.exe --json')

    def test_external_connection_commands_are_protected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            values = {'calendar': {'enabled': True, 'kind': 'external'},
                      'claude': {'enabled': True, 'source': 'external'},
                      'secrets': {'calendar_command': ['local-reader.exe', 'calendar'],
                                  'claude_command': ['local-reader.exe', 'claude']}}
            validate(values, root)
            save_connection(values, root)
            self.assertNotIn('local-reader.exe', (root / 'connections.json').read_text())
            self.assertNotIn(b'local-reader.exe', (root / 'connections.sealed').read_bytes())

    def test_discovery_does_not_claim_account_authorization(self):
        settings = json.loads(json.dumps(DEFAULTS))
        with patch('discovery.executable', side_effect=FileNotFoundError), patch('discovery.shutil.which', return_value=None):
            result = discover(settings)
        self.assertFalse(result['codex_installed'])
        self.assertFalse(result['claude_installed'])
        self.assertNotIn('authorized', result)


if __name__ == '__main__':
    unittest.main()
