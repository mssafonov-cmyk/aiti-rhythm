import unittest
from datetime import datetime,timezone
from local_metrics import SessionState

class SessionTests(unittest.TestCase):
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
