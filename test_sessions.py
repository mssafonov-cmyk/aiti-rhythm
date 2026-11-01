import unittest
import json
import tempfile
from pathlib import Path
from datetime import datetime,timezone
from local_metrics import SessionState
from local_metrics import codex_local

class SessionTests(unittest.TestCase):
    def test_account_switch_invalidates_sessions_and_quota_but_preserves_profile_history(self):
        from collector_service import Collector
        from runtime import DEFAULTS
        import copy
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);settings=copy.deepcopy(DEFAULTS);settings['codex']['home']=str(root)
            collector=Collector(root)
            try:
                def identity(owner):
                    (root/'auth.json').write_text(json.dumps(dict(tokens=dict(account_id=owner))))
                    return collector.key('codex',settings),collector.key('limits',settings),collector.history_identity('codex',settings)
                first=identity('personal');second=identity('work')
                self.assertNotEqual(first[0],second[0]);self.assertNotEqual(first[1],second[1]);self.assertEqual(first[2],second[2])
            finally:collector.close()

    def test_account_switch_filters_sessions_without_inventing_billing_attribution(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);(root/'sessions').mkdir()
            at=datetime.now(timezone.utc).isoformat()
            for index,owner in enumerate(('personal','work',None)):
                rows=[dict(type='session_meta',timestamp=at,payload=dict(id=str(index),creator_account_id=owner,cwd='project')),
                      dict(type='event_msg',timestamp=at,payload=dict(type='task_started')),
                      dict(type='event_msg',timestamp=at,payload=dict(type='token_count',info=dict(total_token_usage=dict(input_tokens=100,output_tokens=10))))]
                (root/'sessions'/f'{index}.jsonl').write_text(''.join(json.dumps(r)+'\n' for r in rows))
            for owner,expected in [('personal','0'),('work','1')]:
                (root/'auth.json').write_text(json.dumps(dict(tokens=dict(account_id=owner))))
                result=codex_local(root)
                self.assertEqual([r['id'] for r in result['sessions']],[expected])
                self.assertEqual(result['excluded_sessions'],2)
                self.assertEqual(result['tokens']['input'],300)
                self.assertEqual(result['token_scope'],'profile')
            (root/'auth.json').unlink()
            self.assertEqual(len(codex_local(root)['sessions']),3)

    def consume(self,s,kind,typ,**fields):
        s.consume({'type':kind,'payload':{'type':typ,**fields}},datetime.now(timezone.utc))

    def test_explicit_wait_and_reply(self):
        s=SessionState()
        self.consume(s,'event_msg','task_started')
        self.consume(s,'response_item','function_call',name='request_user_input_async',call_id='q')
        self.consume(s,'event_msg','task_complete')
        self.assertEqual(s.status,'waiting')
        self.consume(s,'response_item','message',role='user')
        self.consume(s,'event_msg','task_started')
        self.consume(s,'event_msg','task_complete')
        self.assertEqual(s.status,'idle')

    def test_sync_response_and_interruption(self):
        s=SessionState()
        self.consume(s,'event_msg','task_started')
        self.consume(s,'response_item','function_call',name='request_user_input',call_id='q')
        self.assertEqual(s.status,'waiting')
        self.consume(s,'response_item','function_call_output',call_id='q')
        self.assertEqual(s.status,'working')
        self.consume(s,'event_msg','turn_aborted')
        self.assertEqual(s.status,'interrupted')

if __name__=='__main__':unittest.main()
