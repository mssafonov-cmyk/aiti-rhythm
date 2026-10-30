"""Compatibility entry: all launches use the same application lifecycle."""
from rhythm_app import main

if __name__ == '__main__':
    raise SystemExit(main())
