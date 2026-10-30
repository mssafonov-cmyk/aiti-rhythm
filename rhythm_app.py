"""One application entry point for source runs, frozen GUI and hidden worker modes."""
import argparse
import ctypes
import json
import os
from pathlib import Path
import subprocess
import sys
import time


def own_process(pid, program):
    kernel = ctypes.WinDLL('kernel32', use_last_error=True)
    kernel.OpenProcess.argtypes = [ctypes.c_uint32, ctypes.c_int, ctypes.c_uint32]
    kernel.OpenProcess.restype = ctypes.c_void_p
    kernel.QueryFullProcessImageNameW.argtypes = [ctypes.c_void_p, ctypes.c_uint32, ctypes.c_wchar_p, ctypes.POINTER(ctypes.c_uint32)]
    kernel.CloseHandle.argtypes = [ctypes.c_void_p]
    handle = kernel.OpenProcess(0x1000, False, int(pid))
    if not handle:
        return False
    try:
        buffer = ctypes.create_unicode_buffer(32768)
        size = ctypes.c_uint32(len(buffer))
        if not kernel.QueryFullProcessImageNameW(handle, 0, buffer, ctypes.byref(size)):
            return False
        target = Path(buffer.value).resolve()
        expected = [program / 'Rhythm.exe', program / 'RhythmCore.exe'] if getattr(sys, 'frozen', False) else [Path(sys.executable)]
        return any(str(target).casefold() == str(path.resolve()).casefold() for path in expected)
    finally:
        kernel.CloseHandle(handle)


def main():
    if sys.stdout is not None:
        sys.stdout.reconfigure(encoding='utf-8')
    if sys.stderr is not None:
        sys.stderr.reconfigure(encoding='utf-8')
    parser = argparse.ArgumentParser()
    parser.add_argument('--data-dir')
    parser.add_argument('--collector', action='store_true')
    parser.add_argument('--once', action='store_true')
    parser.add_argument('--configure-stdin', action='store_true')
    parser.add_argument('--self-test', action='store_true')
    parser.add_argument('--settings-test', action='store_true')
    parser.add_argument('--settings', action='store_true')
    parser.add_argument('--probe', action='store_true')
    parser.add_argument('--shutdown', action='store_true')
    parser.add_argument('--recover', action='store_true')
    parser.add_argument('--legacy-root')
    parser.add_argument('--legacy-provider', choices=['calendar', 'claude'])
    args = parser.parse_args()
    if args.data_dir:
        os.environ['RHYTHM_DATA_DIR'] = str(Path(args.data_dir).resolve())
    from app_paths import DATA, ASSETS, PROGRAM, VERSION, core_command
    DATA.mkdir(parents=True, exist_ok=True)
    os.environ['RHYTHM_DATA_DIR'] = str(DATA)
    os.environ['RHYTHM_CORE_EXE'] = core_command()[0]
    os.environ['RHYTHM_CORE_PREFIX'] = '' if getattr(sys, 'frozen', False) else '"' + str(ASSETS / 'rhythm_app.py') + '"'
    os.environ['RHYTHM_VERSION'] = VERSION
    build_file = ASSETS / 'build-info.json'
    build_info = json.loads(build_file.read_text(encoding='utf-8')) if build_file.exists() else {}
    os.environ['RHYTHM_BUILD_COMMIT'] = build_info.get('source_commit', 'source')
    if args.recover:
        (DATA / 'collector-restart.signal').write_text('restart')
        return 0
    if args.configure_stdin:
        from configure import main as configure
        return configure()
    if args.collector:
        from collector_service import main as collect
        sys.argv = ['collector'] + (['--once'] if args.once else [])
        return collect()
    if args.legacy_root:
        from legacy_bridge import read
        print(json.dumps(read(args.legacy_root, args.legacy_provider, DATA), ensure_ascii=False))
        return 0
    if args.probe:
        from runtime import load_settings, provider_home
        from codex_account import executable
        settings = load_settings()
        try:
            codex = bool(executable(settings['codex']))
        except FileNotFoundError:
            codex = False
        print(json.dumps({'version': VERSION, 'source_commit': build_info.get('source_commit'), 'frozen': bool(getattr(sys, 'frozen', False)),
            'program': str(PROGRAM), 'data': str(DATA), 'is_admin': bool(ctypes.windll.shell32.IsUserAnAdmin()),
            'codex_found': codex,
            'codex_journals': (provider_home(settings['codex']['home'], 'CODEX_HOME', '.codex') / 'sessions').exists(),
            'claude_journals': (provider_home(settings['claude']['home'], 'CLAUDE_CONFIG_DIR', '.claude') / 'projects').exists()}))
        return 0
    if args.shutdown:
        status = DATA / 'app-status.json'
        if not status.exists():
            return 0
        try:
            running = json.loads(status.read_text(encoding='utf-8'))
        except ValueError:
            running = {}
        if not own_process(running.get('pid', 0), PROGRAM):
            status.unlink(missing_ok=True)
            return 0
        (DATA / 'widget-stop.signal').write_text('stop')
        deadline = time.monotonic() + 20
        while status.exists() and time.monotonic() < deadline:
            time.sleep(.2)
        return 1 if status.exists() else 0
    powershell = str(Path(os.environ['SystemRoot']) / 'System32/WindowsPowerShell/v1.0/powershell.exe')
    from discovery import discover
    from runtime import load_settings
    from safeio import atomic_json
    atomic_json(DATA / 'discovery.json', discover(load_settings()))
    settings_mode = args.settings or args.settings_test
    command = [powershell, '-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-File',
               str(ASSETS / ('connections.ps1' if settings_mode else 'widget.ps1')), '-DataRoot', str(DATA)]
    if args.self_test or args.settings_test:
        command.append('-SelfTest')
    flags = getattr(subprocess, 'CREATE_NO_WINDOW', 0)
    if args.self_test or settings_mode:
        with (DATA / 'ui-test.log').open('ab') as log:
            return subprocess.run(command, stdin=subprocess.DEVNULL, stdout=log, stderr=log, creationflags=flags).returncode
    kernel = ctypes.WinDLL('kernel32', use_last_error=True)
    kernel.CreateMutexW.restype = ctypes.c_void_p
    kernel.CloseHandle.argtypes = [ctypes.c_void_p]
    mutex = kernel.CreateMutexW(None, True, 'Local\\AITI-Rhythm-Application')
    if ctypes.get_last_error() == 183:
        (DATA / 'widget-show.signal').write_text('show')
        kernel.CloseHandle(mutex)
        return 0
    collector = None
    try:
        collector = subprocess.Popen(core_command() + ['--collector'], stdin=subprocess.DEVNULL,
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, creationflags=flags)
        from safeio import atomic_json
        atomic_json(DATA / 'app-status.json', {'pid': os.getpid(), 'collector_pid': collector.pid,
                    'version': VERSION, 'source_commit': build_info.get('source_commit'), 'program': str(PROGRAM), 'started_at': time.time()})
        with (DATA / 'widget-launch.log').open('ab') as log:
            window = subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=log, stderr=log, creationflags=flags)
            while window.poll() is None:
                restart = DATA / 'collector-restart.signal'
                if restart.exists() or collector.poll() is not None:
                    restart.unlink(missing_ok=True)
                    if collector.poll() is None:
                        collector.terminate(); collector.wait(timeout=4)
                    collector = subprocess.Popen(core_command() + ['--collector'], stdin=subprocess.DEVNULL,
                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, creationflags=flags)
                    atomic_json(DATA / 'app-status.json', {'pid': os.getpid(), 'collector_pid': collector.pid,
                                'version': VERSION, 'source_commit': build_info.get('source_commit'), 'program': str(PROGRAM), 'started_at': time.time()})
                time.sleep(.5)
            return window.returncode
    finally:
        if collector and collector.poll() is None:
            collector.terminate()
            try:
                collector.wait(timeout=4)
            except subprocess.TimeoutExpired:
                collector.kill(); collector.wait(timeout=4)
        (DATA / 'app-status.json').unlink(missing_ok=True)
        kernel.CloseHandle(mutex)


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except Exception as error:
        if sys.stderr is not None:
            print(type(error).__name__, file=sys.stderr)
        else:
            ctypes.windll.user32.MessageBoxW(None, 'Не удалось запустить АйТи:Ритм. Проверьте журнал в папке данных.', 'АйТи:Ритм', 16)
        raise SystemExit(1)
