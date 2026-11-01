import unittest
from unittest.mock import patch
import startup


class StartupTests(unittest.TestCase):
    def test_toggle_and_rollback_preserve_original_command(self):
        with patch.object(startup, 'read', return_value='previous'), patch.object(startup, 'restore') as write:
            undo = startup.set_enabled(True)
            write.assert_called_once_with(startup.command())
            undo()
            self.assertEqual(write.call_args.args, ('previous',))
            startup.set_enabled(False)
            self.assertEqual(write.call_args.args, (None,))

    def test_status_uses_registry_and_command_quotes_paths(self):
        with patch.object(startup, 'read', return_value=startup.command()):
            self.assertTrue(startup.enabled())
        with patch.object(startup, 'read', return_value=None):
            self.assertFalse(startup.enabled())
        self.assertIn('--data-dir', startup.command())
        with self.assertRaises(ValueError):
            startup.set_enabled('false')
