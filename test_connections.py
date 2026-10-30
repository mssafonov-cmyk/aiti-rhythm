import copy
from datetime import datetime, timezone
import json
from pathlib import Path
import tempfile
import time
import unittest
from unittest.mock import patch
from calendars import parse_ical, parse_odata, checked_url, collect_calendar
from claude_metrics import claude_local
from codex_account import normalize
from collector_service import Collector
from cube import Cube, host_url, render, encode, page_for
from runtime import DEFAULTS, load_secrets, load_settings, save_connection


class SecretTests(unittest.TestCase):
    def test_disconnect_calendar_retains_independent_claude_settings(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            save_connection({'calendar': {'enabled': True}, 'secrets': {
                'calendar_url': 'fake-calendar', 'claude_command': ['reader.exe', '--json']}}, root)
            save_connection({'calendar': {'enabled': False}}, root)
            self.assertEqual(load_secrets(root), {'claude_command': ['reader.exe', '--json']})

    def test_windows_protection_and_disconnect(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            secret = 'fake-private-calendar-key-for-test'
            save_connection({'calendar': {'enabled': True}, 'secrets': {'calendar_url': secret}}, root)
            self.assertNotIn(secret.encode(), (root / 'connections.sealed').read_bytes())
            self.assertNotIn(secret, (root / 'connections.json').read_text())
            self.assertEqual(load_secrets(root)['calendar_url'], secret)
            save_connection({'calendar': {'enabled': True}, 'secrets': {'calendar_url': ''}}, root)
            self.assertEqual(load_secrets(root)['calendar_url'], secret)
            save_connection({'calendar': {'enabled': False}}, root)
            self.assertEqual(load_secrets(root), {})

    def test_disabled_connections_never_read_secrets_or_network(self):
        with patch('calendars.fetch', side_effect=AssertionError('network')):
            self.assertEqual(collect_calendar(DEFAULTS['calendar'], {})['events'], [])
        cube = Cube()
        with patch.object(cube, 'request', side_effect=AssertionError('network')):
            self.assertFalse(cube.update(DEFAULTS['cube'], {})['enabled'])
        for bad in ('http://calendar.example/calendar', 'https://user:pass@calendar.example/x', 'file:///x'):
            with self.assertRaises(ValueError):
                checked_url(bad)
        for bad in ('0.0.0.0', '8.8.8.8', '224.0.0.1', 'example.com'):
            with self.assertRaises(ValueError):
                host_url(bad)


class CalendarTests(unittest.TestCase):
    def test_recurrence_exception_cancellation_and_all_day(self):
        content = '''BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//Rhythm tests//EN
BEGIN:VEVENT
UID:repeated
DTSTART;TZID=Europe/Moscow:20261030T100000
DTEND;TZID=Europe/Moscow:20261030T110000
RRULE:FREQ=DAILY;COUNT=3
EXDATE;TZID=Europe/Moscow:20261031T100000
SUMMARY:Repeated
DESCRIPTION:https://meet.google.com/abc-defg-hij
END:VEVENT
BEGIN:VEVENT
UID:cancelled
DTSTART:20261030T090000Z
STATUS:CANCELLED
END:VEVENT
BEGIN:VEVENT
UID:all-day
DTSTART;VALUE=DATE:20261030
DTEND;VALUE=DATE:20261031
SUMMARY:Day
END:VEVENT
END:VCALENDAR'''
        rows = parse_ical(content, DEFAULTS['calendar'], datetime(2026, 10, 30, tzinfo=timezone.utc))
        self.assertEqual(len(rows), 3)
        repeated = [row for row in rows if row['subject'] == 'Repeated']
        self.assertEqual(len(repeated), 2)
        self.assertTrue(repeated[0]['planned_date'].endswith('+03:00'))
        self.assertEqual(repeated[0]['telemost_url'], 'https://meet.google.com/abc-defg-hij')
        self.assertTrue(next(row for row in rows if row['subject'] == 'Day')['all_day'])
        self.assertEqual(len({row['ref'] for row in rows}), 3)

    def test_odata_mapping_and_no_silent_truncation(self):
        config = copy.deepcopy(DEFAULTS['calendar'])
        config['mapping'] = dict(id='ref', subject='name', start='date', end='finish', url='join')
        rows = parse_odata(json.dumps({'value': [{'ref': 'sample', 'name': 'Meeting', 'date': '2026-10-30T10:00:00'}]}),
                           config, datetime(2026, 10, 30, tzinfo=timezone.utc))
        self.assertEqual(rows[0]['planned_date'], '2026-10-30T10:00:00+03:00')
        with self.assertRaises(ValueError):
            parse_odata('{"value":[],"@odata.nextLink":"next"}', config)


class AgentTests(unittest.TestCase):
    def test_codex_windows_do_not_invent_quota(self):
        value = normalize({'rateLimits': {'primary': {'usedPercent': 30, 'windowDurationMins': 300},
                                          'secondary': {'usedPercent': 16.3, 'windowDurationMins': 10080, 'resetsAt': 42}}})
        self.assertAlmostEqual(value['weekly_pct'], .163)
        self.assertEqual(value['weekly_reset_at'], 42)
        self.assertEqual(normalize({})['error'], 'quota_not_available')

    def test_claude_deduplicates_streamed_usage_without_message_text(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            folder = home / 'projects' / 'test'; folder.mkdir(parents=True)
            now = time.time()
            rows = []
            for output in (2, 7):
                rows.append({'type': 'assistant', 'timestamp': datetime.fromtimestamp(now, timezone.utc).isoformat(),
                             'sessionId': 'sample', 'message': {'id': 'one-message', 'stop_reason': 'end_turn',
                             'content': [{'type': 'text', 'text': 'SECRET BODY NOT FOR SNAPSHOT'}],
                             'usage': {'input_tokens': 10, 'output_tokens': output, 'cache_read_input_tokens': 3}}})
            (folder / 'sample.jsonl').write_text('\n'.join(json.dumps(row) for row in rows) + '\n', encoding='utf-8')
            result = claude_local(home, now + 1)
            self.assertEqual(result['tokens'], {'input': 13, 'output': 7, 'cache': 3})
            self.assertEqual(result['sessions'][0]['status'], 'idle')
            self.assertNotIn('SECRET BODY', json.dumps(result))
            self.assertNotIn('limits', result)

    def test_claude_cache_waits_for_complete_lines_and_keeps_no_body(self):
        from claude_metrics import metadata_rows, _cache
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'sample.jsonl'
            now = time.time()
            row = json.dumps({'type': 'user', 'timestamp': datetime.fromtimestamp(now, timezone.utc).isoformat(),
                              'message': {'content': 'DO NOT CACHE THIS TEXT'}}).encode()
            path.write_bytes(row)
            self.assertEqual(metadata_rows(path, now + 1), [])
            with path.open('ab') as stream:
                stream.write(b'\n')
            self.assertEqual(len(metadata_rows(path, now + 1)), 1)
            self.assertNotIn('DO NOT CACHE', str(_cache[path]))


class CollectorTests(unittest.TestCase):
    def test_optional_failure_and_disconnect_do_not_block_local_metrics(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            settings = copy.deepcopy(DEFAULTS)
            settings['codex']['limits'] = False
            settings['claude']['enabled'] = False
            settings['calendar']['enabled'] = True
            (root / 'connections.json').write_text(json.dumps(settings))
            collector = Collector(root)
            def work(name, config):
                if name == 'calendar':
                    raise RuntimeError('private URL must never be logged')
                return {'sessions': [], 'checked_at': 123, 'observed': True}
            try:
                with patch.object(collector, 'work', side_effect=work):
                    collector.step(100)
                    for _, future in list(collector.pending.values()):
                        try:
                            future.result(timeout=2)
                        except RuntimeError:
                            pass
                    result = collector.step(101)
                    self.assertTrue(result['codex']['observed'])
                    self.assertEqual(result['calendar']['error'], 'RuntimeError')
                    self.assertNotIn('private URL', json.dumps(result))
                    settings['calendar']['enabled'] = False
                    (root / 'connections.json').write_text(json.dumps(settings))
                    self.assertFalse(collector.step(102)['calendar']['enabled'])
            finally:
                collector.close()


class CubeTests(unittest.TestCase):
    def test_only_own_fixed_filenames_and_safe_metadata_are_sent(self):
        cube = Cube()
        config = dict(DEFAULTS['cube'], enabled=True, host='192.168.50.7')
        requests = []
        def request(path, data=None, headers=None):
            requests.append((path, data))
            return b'{"m":"HelloCubic-Lite"}' if path == '/v.json' else b'OK'
        with patch.object(cube, 'request', side_effect=request):
            result = cube.update(config, {}, 100)
            cube.update(config, {}, 101)
        self.assertEqual(result['checked_at'], 100)
        self.assertEqual(sum(path.startswith('/doUpload') for path, _ in requests), 1)
        self.assertTrue(all('/delete' not in path for path, _ in requests))
        self.assertEqual(encode(render({}, config))[0][:2], b'\xff\xd8')

    def test_unchanged_cube_frames_do_not_rewrite_flash(self):
        cube = Cube()
        config = dict(DEFAULTS['cube'], enabled=True, host='192.168.50.7')
        requests = []
        def request(path, data=None, headers=None):
            requests.append(path)
            return b'{"m":"HelloCubic-Lite"}' if path == '/v.json' else b'OK'
        with patch.object(cube, 'request', side_effect=request):
            for now in (100, 131, 162, 193):
                cube.update(config, {}, now)
        self.assertEqual(sum(path.startswith('/doUpload') for path in requests), 3)
        self.assertEqual(requests.count('/set?theme=2'), 1)

    def test_urgent_meeting_preempts_rotation_and_encodes_native_blink(self):
        from datetime import timedelta
        now = datetime.now(timezone.utc)
        snapshot = {'calendar': {'enabled': True, 'checked_at': now.timestamp(), 'events': [
            {'planned_date': (now + timedelta(minutes=4)).isoformat(), 'subject': 'Private title'}]}}
        self.assertEqual(page_for(snapshot, 0), 'calendar')
        payload, extension = encode(render(snapshot, DEFAULTS['cube']), blink=True)
        self.assertEqual(extension, '.gif')
        self.assertTrue(payload.startswith(b'GIF'))


if __name__ == '__main__':
    unittest.main()
