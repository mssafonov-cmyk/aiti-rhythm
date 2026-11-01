"""Per-user Windows startup. Registry is the source of truth, not saved UI state."""
import subprocess
import sys
from pathlib import Path
import winreg
from app_paths import PROGRAM, ASSETS, DATA

KEY = r'Software\Microsoft\Windows\CurrentVersion\Run'
NAME = 'AITIRhythm'


def command():
    args = [str(PROGRAM / 'Rhythm.exe')] if getattr(sys, 'frozen', False) else [
        str(Path(sys.executable).with_name('pythonw.exe')), str(ASSETS / 'rhythm_app.py')]
    return subprocess.list2cmdline(args + ['--data-dir', str(DATA)])


def read():
    try:
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, KEY) as key:
            return winreg.QueryValueEx(key, NAME)[0]
    except FileNotFoundError:
        return None


def enabled():
    value = read()
    return value in (command(), '"' + str(PROGRAM / 'Rhythm.exe') + '"')


def restore(value):
    with winreg.CreateKey(winreg.HKEY_CURRENT_USER, KEY) as key:
        if value is None:
            try:
                winreg.DeleteValue(key, NAME)
            except FileNotFoundError:
                pass
        else:
            winreg.SetValueEx(key, NAME, 0, winreg.REG_SZ, value)


def set_enabled(value):
    if type(value) is not bool:
        raise ValueError('Startup must be a boolean')
    previous = read()
    restore(command() if value else None)
    return lambda: restore(previous)
