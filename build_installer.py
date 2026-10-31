"""Build a self-contained Windows installer from public assets only."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import shutil
import sys
import tempfile
from app_paths import VERSION


def stage_installer(installer, output):
    """Publish from content-addressed copies; rebuilds never overwrite uploads."""
    digest = hashlib.sha256(installer.read_bytes()).hexdigest()
    folder = output / VERSION / digest
    folder.mkdir(parents=True, exist_ok=True)
    target = folder / installer.name
    if not target.exists():
        with installer.open('rb') as source, target.open('xb') as dest:
            shutil.copyfileobj(source, dest)
    if hashlib.sha256(target.read_bytes()).hexdigest() != digest:
        raise RuntimeError('Staged installer checksum mismatch')
    sums = folder / 'SHA256SUMS.txt'
    expected = digest + '  ' + installer.name + '\n'
    if not sums.exists():
        with sums.open('x', encoding='ascii', newline='\n') as stream:
            stream.write(expected)
    if sums.read_text(encoding='ascii') != expected:
        raise RuntimeError('Staged checksum file mismatch')
    return target, digest


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--iscc', required=True, type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent
    revision = subprocess.run(['git','rev-parse','HEAD'], cwd=root, capture_output=True, text=True)
    info = {'version': VERSION, 'source_commit': revision.stdout.strip() if revision.returncode == 0 else 'development'}
    (root / 'build-info.json').write_text(json.dumps(info, indent=2), encoding='utf-8')
    subprocess.run([sys.executable,'-m','PyInstaller','--noconfirm','--clean','Rhythm.spec'], cwd=root, check=True)
    # Inno's output is isolated even while an earlier release is being uploaded.
    with tempfile.TemporaryDirectory(prefix='rhythm-installer-', dir=root / 'dist') as build_dir:
        subprocess.run([str(args.iscc), '/DVersion=' + VERSION, '/O' + build_dir, 'installer.iss'], cwd=root, check=True)
        installer, digest = stage_installer(Path(build_dir) / ('AITI-Rhythm-' + VERSION + '-Setup.exe'), root / 'dist/releases')
    print(json.dumps(dict(info, installer=str(installer.relative_to(root)), sha256=digest)))


if __name__ == '__main__':
    main()
