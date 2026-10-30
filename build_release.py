"""Export only reviewed source files; build a new repository without private history."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import zipfile

VERSION = '1.1.2'
FILES = (
    'README.md', 'PACKAGE-README.txt', 'LICENSE', 'THIRD-PARTY-NOTICES.md', 'SECURITY.md',
    '.gitignore', '.github/workflows/check.yml', 'requirements.txt', 'requirements-build.txt',
    'CONTRIBUTING.md', 'Rhythm.spec', 'installer.iss', 'build_installer.py',
    'connections.ps1', 'configure.py', 'runtime.py', 'calendars.py', 'cube.py',
    'app_paths.py', 'rhythm_app.py', 'external_reader.py', 'legacy_bridge.py', 'discovery.py',
    'codex_account.py', 'claude_metrics.py', 'collector_service.py', 'local_collector.py',
    'local_metrics.py', 'safeio.py', 'burn.py', 'widget.ps1', 'unified.ps1', 'widget-launch.pyw',
    'indicators.ico', 'unified-test.ps1', 'test_burn.py', 'test_sessions.py', 'test_local_cache.py',
    'test_safeio.py', 'test_connections.py', 'build_release.py',
    'test_installation.py', 'verify_installer.py',
)


def build(source, output):
    output.mkdir(parents=True, exist_ok=True)
    export = output / ('aiti-rhythm-' + VERSION)
    if export.exists():
        raise ValueError('Export already exists; use a new output directory')
    payload = {}
    findings = []
    patterns = {
        'private-key': r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----',
        'token': r'\b(?:sk-(?:proj-|ant-)?[A-Za-z0-9_-]{24,}|gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,})\b',
        'private-origin': r'(?<!\d)10\.\d+\.\d+\.\d+|C:[/\\\\]Users[/\\\\][^/\\\\]+[/\\\\]',
    }
    for name in FILES:
        path = source / name
        if not path.is_file() or path.is_symlink():
            raise ValueError('Missing or linked source: ' + name)
        data = path.read_bytes()
        if path.suffix != '.ico':
            content = data.decode('utf-8-sig')
            # The auditor's own regular expressions contain example origin names.
            if name != 'build_release.py':
                for rule, pattern in patterns.items():
                    if re.search(pattern, content, re.IGNORECASE):
                        findings.append({'file': name, 'rule': rule})
        payload[name] = data
    if findings:
        raise ValueError('Blocked export: ' + json.dumps(findings))
    manifest = {name: hashlib.sha256(data).hexdigest() for name, data in payload.items()}
    payload['manifest.json'] = json.dumps(manifest, indent=2).encode()
    for name, data in payload.items():
        target = export / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
    archive = output / ('aiti-rhythm-' + VERSION + '-windows.zip')
    with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED) as bundle:
        for name, data in payload.items():
            bundle.writestr(name, data)
    with zipfile.ZipFile(archive) as bundle:
        if set(bundle.namelist()) != set(payload) or any(bundle.read(name) != data for name, data in payload.items()):
            raise ValueError('Archive verification failed')
    report = {'version': VERSION, 'files': len(payload), 'sha256': hashlib.sha256(archive.read_bytes()).hexdigest(),
              'heuristic_findings': [], 'source_history_exported': False}
    (output / 'build-report.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(json.dumps(report, indent=2))
    return export, archive


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=Path, default=Path(__file__).resolve().parent / 'dist')
    args = parser.parse_args()
    build(Path(__file__).resolve().parent, args.output)
