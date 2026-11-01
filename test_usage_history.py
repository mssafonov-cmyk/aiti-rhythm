import copy
from datetime import datetime
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from history_readers import read_history, MSK, _files
from usage_history import UsageHistory


class HistoryTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.now = datetime(2026, 11, 1, 12, tzinfo=MSK).timestamp()
        self.ids = {'codex': 'a'*64, 'claude': 'b'*64}
        _files.clear()

    def write(self, folder, name, rows):
        path = self.root/folder/name; path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(''.join(json.dumps(r)+'\n' for r in rows), encoding='utf-8')
        return path

    def token(self, at, count, **extra):
        return dict(type='event_msg', timestamp=at, payload=dict(type='token_count', info=dict(
            total_token_usage=dict(input_tokens=count, output_tokens=count//10, cached_input_tokens=count//2))), **extra)

    def test_codex_retained_archived_duplicate_delta_reset_and_msk(self):
        rows=[dict(type='session_meta', timestamp='2026-10-30T12:00:00Z', payload=dict(id='one')),
              self.token('2026-10-30T20:59:00Z', 100), self.token('2026-10-30T21:01:00Z', 300),
              self.token('2026-10-30T21:02:00Z', 300), self.token('2026-10-31T12:00:00Z', 20)]
        self.write('sessions', 'one.jsonl', rows)
        self.write('archived_sessions', 'copy.jsonl', rows)
        result=read_history(self.root,'codex',self.now)
        self.assertEqual([(r['date'],r['total']) for r in result['days']], [('2026-10-30',110),('2026-10-31',220)])
        self.assertEqual(result,read_history(self.root,'codex',self.now))

    def test_fork_inherited_tokens_not_charged_again(self):
        rows=[dict(type='session_meta',timestamp='2026-11-01T08:00:00Z',payload=dict(id='fork',forked_from_id='parent')),
              self.token('2026-10-31T10:00:00Z',1000),self.token('2026-11-01T08:00:01Z',1100)]
        self.write('sessions','fork.jsonl',rows)
        self.assertEqual(read_history(self.root,'codex',self.now)['days'][0]['total'],110)

    def test_claude_streaming_copies_cache_and_midnight(self):
        def message(count):
            return dict(type='assistant',timestamp='2026-10-31T21:01:00Z',message=dict(id='m',
                content='PRIVATE TEXT',usage=dict(input_tokens=10,output_tokens=count,
                cache_read_input_tokens=100,cache_creation_input_tokens=20)))
        self.write('projects/a','main.jsonl',[message(1),message(8)])
        self.write('projects/b','copy.jsonl',[message(8)])
        result=read_history(self.root,'claude',self.now)
        self.assertEqual(result['days'],[dict(date='2026-11-01',total=138,partial=False)])
        self.assertNotIn('PRIVATE TEXT',str(_files))

    def test_corrupt_tail_marks_partial_and_new_complete_lines_are_read(self):
        path=self.write('sessions','one.jsonl',[self.token('2026-11-01T08:00:00Z',100)])
        with path.open('a') as f:f.write('{')
        self.assertTrue(read_history(self.root,'codex',self.now)['partial'])
        path.write_text(json.dumps(self.token('2026-11-01T08:00:00Z',200))+'\n')
        self.assertEqual(read_history(self.root,'codex',self.now)['days'][0]['total'],220)

    def test_archive_restart_rollover_dedupe_and_identity_isolation(self):
        memory=UsageHistory(self.root)
        snap={'claude':dict(enabled=True,checked_at=self.now,tokens=dict(input=100,output=5))}
        imports={'claude':dict(days=[dict(date='2026-10-30',total=300)],checked_at=self.now)}
        value=memory.enrich(snap,self.ids,imports,self.now)['claude']
        self.assertEqual(sum(r['total'] for r in value['days']),405)
        memory=UsageHistory(self.root)
        value=memory.enrich({},self.ids,imports,self.now+86400)['claude']
        self.assertEqual(sum(r['total'] for r in value['days']),405)
        self.assertEqual(len(value['days']),2)  # Missing day is not manufactured as zero.
        smaller={'claude':dict(days=[dict(date='2026-10-30',total=2)],checked_at=self.now)}
        value=memory.enrich({},self.ids,smaller,self.now+86401)['claude']
        self.assertEqual(value['days'][0]['total'],300)
        switched=memory.enrich({},dict(claude='c'*64),{},self.now+86402)
        self.assertEqual(switched['claude']['days'],[])
        self.assertEqual(memory.enrich({},self.ids,{},self.now+86403)['claude']['days'][0]['total'],300)

    def test_invalid_future_error_and_disk_failure(self):
        memory=UsageHistory(self.root)
        imports={'claude':dict(days=[dict(date='2026-10-31',total=0),dict(date='2026-11-02',total=1),
                                     dict(date='bad',total=3),dict(date='2026-10-30',total=-1)])}
        with patch('usage_history.atomic_json',side_effect=OSError):
            value=memory.enrich({},self.ids,imports,self.now)['claude']
            self.assertTrue(value['save_error']);self.assertEqual(len(value['days']),1)
        value=memory.enrich({},self.ids,{'claude':dict(error='TimeoutError')},self.now+16)['claude']
        self.assertTrue(value['error']);self.assertEqual(value['days'][0]['total'],0)
        self.assertFalse(value['save_error'])
        self.assertNotIn('command',memory.path.read_text())

    def test_history_identity_survives_unrelated_settings(self):
        from collector_service import Collector
        from runtime import DEFAULTS
        settings=copy.deepcopy(DEFAULTS);collector=Collector(self.root)
        try:
            first=collector.history_identity('codex',settings)
            settings['codex']['enabled']=False;settings['codex']['limits']=False
            self.assertEqual(first,collector.history_identity('codex',settings))
            settings['codex']['home']='another-profile'
            self.assertNotEqual(first,collector.history_identity('codex',settings))
        finally:collector.close()

    def test_remote_history_reuses_host_without_quota_http(self):
        from legacy_bridge import read_token_history
        fixture = """import json,io
from contextlib import redirect_stdout
def ssh(host, source):
    assert host == 'configured-host'
    out=io.StringIO()
    with redirect_stdout(out): exec(source,{})
    return json.loads(out.getvalue())
def claude_remote():
    return ssh('configured-host', 'raise RuntimeError(\"quota must not run\")')
"""
        legacy=self.root/'legacy';legacy.mkdir();(legacy/'collect.py').write_text(fixture)
        self.write('.claude/projects/test','sample.jsonl',[dict(type='assistant',timestamp='2026-10-31T12:00:00Z',
            message=dict(id='m',usage=dict(input_tokens=10,output_tokens=5)))])
        with patch('pathlib.Path.home',return_value=self.root), patch('urllib.request.urlopen') as http:
            result=read_token_history(legacy)
            self.assertEqual(result['days'][0]['total'],15);http.assert_not_called()

    def test_antigravity_daily_steps_cache_isolated_from_live_worker(self):
        from antigravity_metrics import usage_rows, _cache
        folder='brain/00000000-0000-0000-0000-000000000001/.system_generated/logs'
        row=dict(type='PLANNER_RESPONSE',step_index=0,created_at='2026-10-31T20:59:00Z',
                 input_tokens=100,output_tokens=20,cache_read_tokens=80)
        path=self.write(folder,'transcript.jsonl',[row,dict(row),dict(row,step_index=1,created_at='2026-10-31T21:01:00Z',output_tokens=40)])
        usage_rows(path);before=copy.deepcopy(_cache[path])
        result=read_history(self.root,'antigravity',self.now)
        self.assertEqual([(d['date'],d['total']) for d in result['days']], [('2026-10-31',120),('2026-11-01',140)])
        self.assertEqual(_cache[path],before)
        self.assertEqual(read_history(self.root,'antigravity',self.now),result)


if __name__=='__main__':unittest.main()
