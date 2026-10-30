"""Build a self-contained Windows installer from public assets only."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
from app_paths import VERSION


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--iscc', required=True, type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent
    revision = subprocess.run(['git','rev-parse','HEAD'], cwd=root, capture_output=True, text=True)
    info = {'version': VERSION, 'source_commit': revision.stdout.strip() if revision.returncode == 0 else 'development'}
    (root / 'build-info.json').write_text(json.dumps(info, indent=2), encoding='utf-8')
    subprocess.run([sys.executable,'-m','PyInstaller','--noconfirm','--clean','Rhythm.spec'], cwd=root, check=True)
    subprocess.run([str(args.iscc), '/DVersion=' + VERSION, 'installer.iss'], cwd=root, check=True)
    installer = root / 'dist/installer' / ('AITI-Rhythm-' + VERSION + '-Setup.exe')
    digest = hashlib.sha256(installer.read_bytes()).hexdigest()
    (installer.parent / 'SHA256SUMS.txt').write_text(digest + '  ' + installer.name + '\n', encoding='ascii')
    print(json.dumps(dict(info, installer=installer.name, sha256=digest)))


if __name__ == '__main__':
    main()
