import json
from contextlib import closing
from pathlib import Path
import sqlite3
import tempfile
import unittest
from unittest.mock import patch
from uuid import uuid4
from antigravity_metrics import antigravity_local, _cache
from usage_metrics import combined_usage


class AntigravityTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.sid = str(uuid4())
        self.path = self.root / 'brain' / self.sid / '.system_generated/logs/transcript.jsonl'
        self.path.parent.mkdir(parents=True)
        self.now = 1793451600  # 31 Oct2026, MSK daytime
        self.addCleanup(_cache.clear)
        self.patcher = patch('antigravity_metrics.installed', return_value=False)
        self.patcher.start(); self.addCleanup(self.patcher.stop)

    def row(self, inp=100, out=20, cache=30):
        from datetime import datetime, timezone
        return dict(type='PLANNER_RESPONSE', step_index=2, status='DONE',
                    created_at=datetime.fromtimestamp(self.now - 30, timezone.utc).isoformat(),
                    input_tokens=inp, output_tokens=out, cache_read_tokens=cache, content='SECRET_MESSAGE')

    def write(self, rows):
        self.path.write_text(''.join(json.dumps(r)+'\n' for r in rows), encoding='utf-8')

    def test_native_counters_dedup_partial_tail_and_cache_privacy(self):
        self.write([self.row(), self.row(150)])
        r = antigravity_local(self.root, self.now)
        self.assertEqual(r['tokens'], dict(input=150, output=20, cache=30))
        self.assertEqual(sum(x['tokens'] for x in r['burn']['series']),170)
        self.assertNotIn('SECRET_MESSAGE', repr(_cache))
        with self.path.open('ab') as f: f.write(json.dumps(dict(self.row(200),step_index=3)).encode())
        self.assertEqual(antigravity_local(self.root,self.now)['tokens']['input'],150)
        with self.path.open('ab') as f: f.write(b'\n')
        self.assertEqual(antigravity_local(self.root,self.now)['tokens']['input'],350)
        self.write([self.row(5,2,1)])
        self.assertEqual(antigravity_local(self.root,self.now)['tokens']['input'],5)

    def test_read_only_summary_real_status_and_unknown_stale(self):
        path = self.root/'conversation_summaries.db'
        with closing(sqlite3.connect(path)) as c:
            c.execute('create table conversation_summaries(conversation_id text,title text,status text,last_modified_time text,preview text)')
            c.execute('insert into conversation_summaries values(?,?,?,?,?)',(self.sid,'Example','CASCADE_RUN_STATUS_RUNNING',self.row()['created_at'],'SECRET_PREVIEW'))
            c.commit()
        before=path.read_bytes()
        self.write([self.row()])
        r=antigravity_local(self.root,self.now)
        self.assertEqual(r['sessions'][0]['status'],'working')
        self.assertNotIn('SECRET_PREVIEW',repr(r))
        self.assertEqual(path.read_bytes(),before)
        self.assertEqual(antigravity_local(self.root,self.now+3600)['sessions'][0]['status'],'unknown')

    def test_absent_and_no_tokens_are_not_zero_measurements(self):
        r=antigravity_local(self.root/'missing',self.now)
        self.assertFalse(r['available'])
        self.assertFalse(combined_usage({'antigravity':r},self.now)['providers'][-1]['name']=='Antigravity')
        self.write([dict(type='USER_INPUT',content='PRIVATE')])
        r=antigravity_local(self.root,self.now)
        self.assertFalse(r['observed'])
        r['enabled']=True
        p=combined_usage({'antigravity':r},self.now)['providers'][-1]
        self.assertIsNone(p['per_min']);self.assertEqual(p['series'],[])

    def test_shared_series_does_not_invent_remote_history(self):
        self.write([self.row()]);r=antigravity_local(self.root,self.now)
        u=combined_usage({'antigravity':r,'claude':dict(checked_at=self.now,tokens=dict(input=777,output=3))},self.now)
        self.assertEqual(u['providers'][-2]['day_tokens'],780)
        self.assertEqual(u['providers'][-2]['series'],[])
        self.assertTrue(u['partial'])  # A daily total cannot establish the current rate.
        self.assertEqual(sum(b['tokens'] for b in u['burn']['series']),120)
        self.assertEqual(u['burn']['leaders'][0]['provider'],'Antigravity')
        r['checked_at']=self.now-181
        self.assertEqual(combined_usage({'antigravity':r},self.now)['providers'][-1]['series'],[])

    def test_bad_or_oversized_rows_mark_lower_bound(self):
        self.write([self.row(),dict(self.row(),step_index=3,input_tokens=-10),dict(self.row(),step_index=4,content='x'*(1024*1024))])
        r=antigravity_local(self.root,self.now)
        self.assertEqual(r['tokens']['input'],100)
        self.assertTrue(r['usage_partial'])
        self.assertTrue(combined_usage({'antigravity':r},self.now)['partial'])


if __name__ == '__main__':
    unittest.main()
