"""Settings bridge: receive secrets via stdin, return no private connection values."""
import json
import sys
import copy
from zoneinfo import ZoneInfo
from calendars import checked_url
from cube import host_url
from runtime import HERE, load_secrets, load_settings, save_connection


def validate(values, root=HERE):
    if 'startup' in values and type(values['startup']) is not bool:
        raise ValueError('Startup must be a boolean')
    current = load_settings(root)
    combined_secrets = dict(load_secrets(root), **{key: value for key, value in values.get('secrets', {}).items() if value})
    claude = dict(current['claude'], **values.get('claude', {}))
    if claude.get('enabled') and claude.get('source') == 'external':
        if not isinstance(combined_secrets.get('claude_command'), list) or not combined_secrets['claude_command']:
            raise ValueError('Configure the external Claude reader')
    calendar = dict(current['calendar'], **values.get('calendar', {}))
    cube = dict(current['cube'], **values.get('cube', {}))
    ZoneInfo(calendar['timezone'])
    if calendar['enabled']:
        if calendar['kind'] not in ('ical', 'caldav', 'odata', 'external'):
            raise ValueError('Choose iCal, CalDAV or OData')
        secrets = dict(load_secrets(root), **{key: value for key, value in values.get('secrets', {}).items() if value})
        if calendar['kind'] == 'external':
            if not isinstance(combined_secrets.get('calendar_command'), list) or not combined_secrets['calendar_command']:
                raise ValueError('Configure the external calendar reader')
        else:
            checked_url(secrets.get('calendar_url', ''))
        if calendar['kind'] == 'caldav' and not secrets.get('calendar_username'):
            raise ValueError('CalDAV requires your account name')
    if cube['enabled']:
        host_url(cube['host'])
    if cube.get('rotation', 0) not in (0, 90, 180, 270):
        raise ValueError('Choose a right-angle cube rotation')
    return values


def main():
    try:
        sys.stdin.reconfigure(encoding='utf-8')
        values = validate(json.load(sys.stdin))
        previous = load_settings()
        desired = copy.deepcopy(previous)
        for key in desired:
            if isinstance(values.get(key), dict):desired[key].update(values[key])
        from antigravity_quota import sync_capture
        from app_paths import core_command
        undo = sync_capture(previous, desired, HERE, core_command())
        try:
            if 'startup' in values:
                from startup import set_enabled
                undo.append(set_enabled(values['startup']))
            save_connection(values)
        except Exception:
            for rollback in reversed(undo):rollback()
            raise
        print('Saved')
    except Exception:
        # Never print exception text: libraries may embed a URL/password in it.
        print('Check the connection fields. Calendar needs HTTPS; cube needs a private IPv4 address.', file=sys.stderr)
        raise SystemExit(1)


if __name__ == '__main__':
    main()
