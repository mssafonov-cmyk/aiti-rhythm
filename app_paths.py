"""Immutable shipped assets and private per-user data are deliberately separate."""
import os
from pathlib import Path
import sys

VERSION = '1.1.3'
ASSETS = Path(__file__).resolve().parent
PROGRAM = Path(sys.executable).resolve().parent if getattr(sys, 'frozen', False) else ASSETS
DATA = Path(os.environ.get('RHYTHM_DATA_DIR') or Path(os.environ.get('LOCALAPPDATA', Path.home() / 'AppData/Local')) / 'AITI/Rhythm/data')


def core_command():
    if getattr(sys, 'frozen', False):
        return [str(PROGRAM / 'RhythmCore.exe')]
    return [sys.executable, str(ASSETS / 'rhythm_app.py')]
