import json
import tempfile
import unittest
from pathlib import Path
from local_metrics import session_records, _session_cache

def event(name):
    return json.dumps(dict(type='event_msg',timestamp='2026-10-26T10:00:00Z',payload=dict(type=name))).encode()+b'\n'

class CacheTest(unittest.TestCase):
    def test_append_partial_and_truncate(self):
        with tempfile.TemporaryDirectory() as directory:
            p=Path(directory)/'session.jsonl'
            first=event('task_started');second=event('task_complete')
            p.write_bytes(first+second[:20])
            self.assertEqual(len(session_records(p)),1)
            self.assertEqual(_session_cache[p]['offset'],len(first))
            with p.open('ab') as f:f.write(second[20:])
            self.assertEqual(len(session_records(p)),2)
            self.assertEqual(len(session_records(p)),2)
            p.write_bytes(first)
            self.assertEqual(len(session_records(p)),1)

    def test_does_not_cache_message_body(self):
        with tempfile.TemporaryDirectory() as directory:
            p=Path(directory)/'session.jsonl'
            p.write_text(json.dumps(dict(type='response_item',timestamp='2026-10-26T10:00:00Z',
                payload=dict(role='user',content='private body')))+'\n',encoding='utf-8')
            self.assertEqual(session_records(p)[0]['payload'],{'role':'user'})

if __name__=='__main__':unittest.main()
