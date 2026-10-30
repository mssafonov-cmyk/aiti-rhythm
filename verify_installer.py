"""Per-user install/upgrade/uninstall acceptance; requires a profile without this app installed."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time
import winreg


def verify(installer, root):
    key = r'Software\Microsoft\Windows\CurrentVersion\Uninstall\{C3878BC6-5661-4EF2-9444-402206FE98F3}_is1'
    try:
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, key):
            raise RuntimeError('Use a separate Windows profile: this application is already installed')
    except FileNotFoundError:
        pass
    if root.exists() and any(root.iterdir()):
        raise RuntimeError('Acceptance destination must be empty')
    root.mkdir(parents=True, exist_ok=True)
    program, data = root / 'program', root / 'data'
    env = dict(os.environ, RHYTHM_DATA_DIR=str(data), PYTHONHOME=str(root / 'no-python'),
               PYTHONPATH=str(root / 'no-python'), PATH=os.environ['SystemRoot'] + r'\System32')
    def run(command, **kwargs):
        return subprocess.run([str(value) for value in command], env=env, capture_output=True,
                              timeout=120, check=True, creationflags=subprocess.CREATE_NO_WINDOW, **kwargs)
    def setup(log):
        run([installer, '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/CURRENTUSER',
             '/DIR=' + str(program), '/TASKS=', '/LOG=' + str(root / log)])
    setup('install.log')
    core, gui = program / 'RhythmCore.exe', program / 'Rhythm.exe'
    probe = json.loads(run([core, '--probe']).stdout)
    if not probe['frozen'] or probe['is_admin']:
        raise AssertionError('Application is not self-contained or is elevated')
    run([core, '--self-test'])
    run([core, '--settings-test'])
    run([core, '--collector', '--once'])
    values = {'secrets': {'claude_command': ['synthetic-reader.exe', '--test']}}
    run([core, '--configure-stdin'], input=json.dumps(values).encode('utf-8'))
    before = {name: hashlib.sha256((data / name).read_bytes()).hexdigest()
              for name in ('connections.json', 'connections.sealed')}
    first = subprocess.Popen([str(gui)], env=env, creationflags=subprocess.CREATE_NO_WINDOW)
    status = data / 'app-status.json'
    try:
        deadline = time.monotonic() + 15
        while not status.exists() and time.monotonic() < deadline:
            if first.poll() is not None:
                raise AssertionError('GUI stopped before startup completed')
            time.sleep(.2)
        old_status = json.loads(status.read_text())
        second = subprocess.Popen([str(gui)], env=env, creationflags=subprocess.CREATE_NO_WINDOW)
        second.wait(timeout=10)
        if json.loads(status.read_text())['pid'] != old_status['pid']:
            raise AssertionError('Repeated launch created a second application')
        # Upgrade while running: the installer must shut down the exact application.
        setup('upgrade.log')
        first.wait(timeout=15)
        if status.exists():
            raise AssertionError('Upgrade did not stop the application')
        for name, digest in before.items():
            if hashlib.sha256((data / name).read_bytes()).hexdigest() != digest:
                raise AssertionError('Upgrade changed private settings')
        run([core, '--self-test'])
        run([program / 'unins000.exe', '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART',
             '/LOG=' + str(root / 'uninstall.log')])
        if gui.exists() or not (data / 'connections.sealed').exists():
            raise AssertionError('Uninstall did not remove application or preserve private data')
    finally:
        if first.poll() is None and core.exists():
            run([core, '--shutdown'])
            first.wait(timeout=15)
    report = dict(version=probe['version'], is_admin=probe['is_admin'], frozen=probe['frozen'],
                  python_removed_from_path=True, bogus_pythonhome=True, install=True, settings=True,
                  ui_self_test=True, collector=True, single_instance=True, upgrade_while_running=True,
                  private_settings_preserved=True, uninstall=True)
    (root / 'acceptance.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(json.dumps(report))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--installer', required=True, type=Path)
    parser.add_argument('--work-dir', required=True, type=Path)
    args = parser.parse_args()
    verify(args.installer.resolve(), args.work_dir.resolve())
