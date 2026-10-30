# Build two entry points sharing one interpreter and dependency directory.
from PyInstaller.utils.hooks import collect_data_files, copy_metadata
from pathlib import Path
import json

root = Path(SPECPATH)
datas = [(str(root / name), '.') for name in ('widget.ps1','unified.ps1','connections.ps1',
         'unified-test.ps1','indicators.ico','LICENSE','THIRD-PARTY-NOTICES.md','build-info.json')]
datas += collect_data_files('tzdata')
for package in ('Pillow','icalendar','recurring-ical-events','caldav'):
    datas += copy_metadata(package, recursive=True)
analysis = Analysis([str(root / 'rhythm_app.py')], pathex=[str(root)], binaries=[], datas=datas,
                    hiddenimports=['shlex','inspect','dataclasses','logging.handlers','multiprocessing',
                                   'icalendar','recurring_ical_events','caldav'],
                    hookspath=[], runtime_hooks=[], excludes=['tkinter','pytest','IPython'])
pyz = PYZ(analysis.pure)
gui = EXE(pyz, analysis.scripts, [], exclude_binaries=True, name='Rhythm', console=False,
          icon=str(root / 'indicators.ico'), uac_admin=False, upx=False)
core = EXE(pyz, analysis.scripts, [], exclude_binaries=True, name='RhythmCore', console=True,
           icon=str(root / 'indicators.ico'), uac_admin=False, upx=False)
bundle = COLLECT(gui, core, analysis.binaries, analysis.datas, name='Rhythm', upx=False)
