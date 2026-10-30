import ctypes
import json
import tempfile
import threading
import unittest
from pathlib import Path
from unittest.mock import patch
from safeio import atomic_json


class AtomicTests(unittest.TestCase):
    def test_windows_reader_lock_is_retried(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'data.json'
            atomic_json(path, {'value': 'old'})
            kernel = ctypes.WinDLL('kernel32', use_last_error=True)
            kernel.CreateFileW.argtypes = [ctypes.c_wchar_p, ctypes.c_uint, ctypes.c_uint,
                                          ctypes.c_void_p, ctypes.c_uint, ctypes.c_uint, ctypes.c_void_p]
            kernel.CreateFileW.restype = ctypes.c_void_p
            kernel.CloseHandle.argtypes = [ctypes.c_void_p]
            handle = kernel.CreateFileW(str(path), 0x80000000, 1, None, 3, 0, None)
            self.assertNotEqual(handle, ctypes.c_void_p(-1).value)
            release = threading.Timer(0.15, lambda: kernel.CloseHandle(handle))
            release.start()
            try:
                atomic_json(path, {'value': 'new'})
                self.assertEqual(json.loads(path.read_text()), {'value': 'new'})
            finally:
                release.join()

    def test_persistent_lock_retains_last_good_data(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'data.json'
            atomic_json(path, {'value': 'old'})
            with patch.object(Path, 'replace', side_effect=PermissionError('locked')) as replace:
                with patch('safeio.time.sleep'), self.assertRaises(PermissionError):
                    atomic_json(path, {'value': 'new'})
                self.assertEqual(replace.call_count, 8)
            self.assertEqual(json.loads(path.read_text()), {'value': 'old'})


if __name__ == '__main__':
    unittest.main()
