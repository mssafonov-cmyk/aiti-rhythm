"""Read-only iCalendar, CalDAV and mapped OData sources, configured by their owner."""
import base64
from datetime import date, datetime, time as wall_time, timedelta, timezone
import hashlib
import json
import re
import time
from urllib.parse import urlparse
from urllib.request import Request, build_opener, HTTPRedirectHandler
from zoneinfo import ZoneInfo


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise ValueError('Calendar redirect is not allowed')


def checked_url(value):
    parsed = urlparse(value)
    if parsed.scheme != 'https' or not parsed.hostname or parsed.username or parsed.password:
        raise ValueError('A direct HTTPS calendar URL without embedded login is required')
    return value


def fetch(url, username='', password=''):
    headers = {'User-Agent': 'AITI-Rhythm/1.0', 'Accept': 'text/calendar, application/json'}
    if username:
        token = base64.b64encode((username + ':' + password).encode()).decode('ascii')
        headers['Authorization'] = 'Basic ' + token
    request = Request(checked_url(url), headers=headers, method='GET')
    with build_opener(NoRedirect).open(request, timeout=12) as response:
        data = response.read(5 * 1024 * 1024 + 1)
    if len(data) > 5 * 1024 * 1024:
        raise ValueError('Calendar response is too large')
    return data


def aware(value, tz):
    if isinstance(value, datetime):
        return value.replace(tzinfo=tz) if value.tzinfo is None else value
    if isinstance(value, date):
        return datetime.combine(value, wall_time.min, tzinfo=tz)
    return aware(datetime.fromisoformat(str(value).replace('Z', '+00:00')), tz)


def event_row(uid, subject, start, end, link, name, all_day=False):
    urls = re.findall(r'https://[^\s<>"\\]+', str(link))
    url = next((value.rstrip('.,;)') for value in urls if urlparse(value).hostname in
                ('telemost.360.yandex.ru', 'telemost.yandex.ru', 'meet.google.com', 'zoom.us') or
                (urlparse(value).hostname or '').endswith('.zoom.us')), '')
    identity = str(uid) + '|' + start.isoformat()
    return dict(ref=hashlib.sha256(identity.encode()).hexdigest()[:24], subject=str(subject or 'Без названия')[:500],
                planned_date=start.isoformat(), planned_end=end.isoformat(), telemost_url=url,
                all_day=all_day, source=name)


def parse_ical(content, config, now=None):
    from icalendar import Calendar
    import recurring_ical_events
    tz = ZoneInfo(config.get('timezone', 'Europe/Moscow'))
    now = now or datetime.now(timezone.utc)
    begin, finish = now - timedelta(days=7), now + timedelta(days=14)
    calendar = Calendar.from_ical(content)
    originals = calendar.walk('VEVENT')
    if len(originals) > 2000:
        raise ValueError('Too many calendar events')
    for item in originals:
        rule = item.get('RRULE')
        if rule and any(str(freq) not in ('DAILY', 'WEEKLY', 'MONTHLY', 'YEARLY') for freq in rule.get('FREQ', [])):
            raise ValueError('Sub-daily calendar recurrence is not supported')
    rows = {}
    for item in recurring_ical_events.of(calendar).between(begin, finish):
        if str(item.get('STATUS', '')).upper() == 'CANCELLED' or 'DTSTART' not in item:
            continue
        start_raw = item.decoded('DTSTART')
        start = aware(start_raw, tz)
        end = aware(item.decoded('DTEND'), tz) if 'DTEND' in item else start + (
            item.decoded('DURATION') if 'DURATION' in item else timedelta(days=1) if not isinstance(start_raw, datetime) else timedelta(minutes=30))
        row = event_row(item.get('UID', ''), item.get('SUMMARY', ''), start, end,
                        str(item.get('URL', '')) + ' ' + str(item.get('LOCATION', '')) + ' ' + str(item.get('DESCRIPTION', '')),
                        config.get('name', '') or str(calendar.get('X-WR-CALNAME', 'Календарь')),
                        not isinstance(start_raw, datetime))
        rows[row['ref']] = row
        if len(rows) > 3000:
            raise ValueError('Expanded calendar is too large')
    return sorted(rows.values(), key=lambda row: row['planned_date'])


def parse_odata(content, config, now=None):
    payload = json.loads(content)
    if '@odata.nextLink' in payload or 'odata.nextLink' in payload:
        raise ValueError('OData pagination requires a narrower configured query')
    mapping = config['mapping']
    tz = ZoneInfo(config.get('timezone', 'Europe/Moscow'))
    now = now or datetime.now(timezone.utc)
    rows = []
    for item in payload.get('value', []):
        start = aware(item[mapping['start']], tz)
        end_value = item.get(mapping['end'])
        end = aware(end_value, tz) if end_value else start + timedelta(minutes=30)
        if end < now - timedelta(days=7) or start > now + timedelta(days=14):
            continue
        rows.append(event_row(item[mapping['id']], item.get(mapping['subject'], ''), start, end,
                              item.get(mapping['url'], ''), config.get('name', 'OData')))
    return sorted(rows, key=lambda row: aware(row['planned_date'], tz))


def collect_calendar(config, secrets):
    if not config['enabled']:
        return {'enabled': False, 'events': [], 'checked_at': time.time()}
    kind = config['kind']
    if kind == 'caldav':
        import caldav
        url = checked_url(secrets.get('calendar_url', ''))
        # A direct calendar collection avoids account-wide discovery.
        with caldav.DAVClient(url=url, username=secrets.get('calendar_username', ''),
                              password=secrets.get('calendar_password', ''), timeout=12) as client:
            calendar = client.calendar(url=url)
            now = datetime.now(timezone.utc)
            results = calendar.search(start=now - timedelta(days=7), end=now + timedelta(days=14), event=True, expand=True)
            if len(results) > 2000:
                raise ValueError('Too many calendar events')
            events = []
            for result in results:
                events.extend(parse_ical(result.data, config, now))
    else:
        content = fetch(secrets.get('calendar_url', ''), secrets.get('calendar_username', ''), secrets.get('calendar_password', ''))
        events = parse_odata(content, config) if kind == 'odata' else parse_ical(content, config)
    # Keep full offsets; order by absolute time across different time zones.
    events.sort(key=lambda row: aware(row['planned_date'], timezone.utc))
    return {'enabled': True, 'events': events, 'checked_at': time.time(),
            'synced_at': datetime.now(timezone.utc).isoformat(), 'source': config.get('name', '') or kind,
            'account': secrets.get('calendar_username', ''), 'kind': kind}
