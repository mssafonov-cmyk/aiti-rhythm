import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import urllib.error
from claude_usage import ClaudeQuotaMemory, preserve_reset_metadata, retry_seconds
from legacy_bridge import read


# Synthetic legacy adapter with the same subprocess lifetime and old-file fallback.
FIXTURE = '''import json,time,io
from contextlib import redirect_stdout
_claude_limits={}
_claude_limits_at=None
_claude_last_attempt=0
def ssh(host, source):
    out=io.StringIO()
    with redirect_stdout(out):exec(source,{})
    return json.loads(out.getvalue())
def claude_remote():
    global _claude_last_attempt
    refresh=time.time()-_claude_last_attempt>=180
    if refresh:_claude_last_attempt=time.time()
    source="import json,time,urllib.request,urllib.error\\n"
    source+="refresh="+repr(refresh)+"\\nlimits="+repr(_claude_limits)+"\\nat="+repr(_claude_limits_at)+"\\n"
    source+="""
if refresh:
    try:
        with urllib.request.urlopen('https://api.anthropic.com/api/oauth/usage') as response:
            raw=json.load(response)
        limits={k:{'used_percentage':v['utilization']} for k,v in raw.items()};at=time.time()
    except (urllib.error.URLError,OSError):
        limits={'seven_day':{'used_percentage':0}};at=123
print(json.dumps({'limits':limits,'limits_at':at,'tokens':{'input':1200,'output':100},'checked_at':time.time()}))
"""
    return ssh('synthetic', source)
'''


class RetryTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.root=Path(self.tmp.name);self.legacy=self.root/'legacy';self.legacy.mkdir()
        (self.legacy/'collect.py').write_text(FIXTURE,encoding='utf-8')
        self.now=1793451600
        self.payload={'seven_day':{'utilization':18,'resets_at':'2026-11-02T20:00:00Z'},'five_hour':{'utilization':0}}

    def run_reader(self, now, error=None):
        with patch('time.time',return_value=now):
            with patch('urllib.request.urlopen',side_effect=error,return_value=io.BytesIO(json.dumps(self.payload).encode())) as http:
                result=read(self.legacy,'claude',self.root)
        return result,http.call_count

    def test_429_wait_survives_new_process_state_and_keeps_fresh_quota_over_old_fallback(self):
        first,calls=self.run_reader(self.now)
        self.assertEqual(calls,1);self.assertEqual(first['limits']['seven_day']['used_percentage'],18)
        error=urllib.error.HTTPError('https://api.anthropic.com/api/oauth/usage',429,'rate limited',{'Retry-After':'7200'},None)
        failed,calls=self.run_reader(self.now+181,error)
        self.assertEqual(calls,1);self.assertEqual(failed['limits_retry_at'],self.now+181+7200)
        self.assertEqual(failed['limits_at'],self.now)
        self.assertEqual(failed['limits']['seven_day']['used_percentage'],18)
        self.assertEqual(failed['limits_error'],'rate_limited')
        # Each read imports a new legacy module and reconstructs remote code from disk state.
        for at in (self.now+362,self.now+7200,self.now+7380):
            held,calls=self.run_reader(at)
            self.assertEqual(calls,0);self.assertEqual(held['tokens']['input'],1200)
            self.assertEqual(held['limits_at'],self.now)
            self.assertEqual(held['limits_retry_at'],self.now+7381)
        fresh,calls=self.run_reader(self.now+7381)
        self.assertEqual(calls,1);self.assertIsNone(fresh['limits_error']);self.assertIsNone(fresh['limits_retry_at'])
        self.assertEqual(fresh['limits_at'],self.now+7381)

    def test_retry_after_http_date_missing_and_bad_values(self):
        self.assertEqual(retry_seconds('Sat, 31 Oct 2026 13:01:00 GMT',self.now),60)
        self.assertEqual(retry_seconds('6000',self.now),6000)
        for invalid in (None,'bad','nan','-1'):
            self.assertEqual(retry_seconds(invalid,self.now),360)
        self.assertEqual(retry_seconds(None,self.now,360),720)

    def test_network_failure_keeps_known_zero_and_unknown_remains_unknown(self):
        fresh,_=self.run_reader(self.now)
        failed,_=self.run_reader(self.now+181,urllib.error.URLError('offline'))
        self.assertEqual(failed['limits']['five_hour']['used_percentage'],0)
        self.assertEqual(failed['limits_at'],fresh['limits_at']);self.assertEqual(failed['limits_error'],'unavailable')
        with patch('time.time',return_value=self.now),patch('urllib.request.urlopen') as http:
            value=preserve_reset_metadata(lambda:{'limits':{},'tokens':{}}, {})
        self.assertEqual(value['limits'],{});http.assert_not_called()

    def test_remote_guard_prevents_http_even_if_legacy_ignores_its_refresh_flag(self):
        previous={'limits_retry_at':self.now+1000,'limits_error':'rate_limited'}
        def ignoring_reader():
            try:
                import urllib.request
                urllib.request.urlopen('https://api.anthropic.com/api/oauth/usage')
            except urllib.error.URLError:pass
            return {'limits':{}}
        with patch('time.time',return_value=self.now),patch('urllib.request.urlopen') as http:
            result=preserve_reset_metadata(ignoring_reader,previous)
        http.assert_not_called();self.assertEqual(result['limits_retry_at'],self.now+1000)

    def test_quota_checkpoint_survives_provider_failure_restart_and_profile_switch(self):
        fresh,_=self.run_reader(self.now)
        fresh.update(enabled=True)
        memory=ClaudeQuotaMemory(self.root);memory.enrich(fresh,'a'*64,self.now)
        restarted=ClaudeQuotaMemory(self.root)
        held=restarted.enrich({'enabled':True,'error':'TimeoutError'},'a'*64,self.now+1000)
        self.assertEqual(held['limits_at'],self.now);self.assertTrue(held['limits_cached'])
        self.assertEqual(held['limits']['seven_day']['used_percentage'],18)
        regressed=memory.enrich(dict(fresh,limits_at=self.now-100),'a'*64,self.now+1)
        self.assertTrue(regressed['limits_cached']);self.assertEqual(regressed['limits_at'],self.now)
        switched=restarted.enrich({'enabled':True},'b'*64,self.now+1001)
        self.assertNotIn('limits',switched)
        disabled=memory.enrich({'enabled':False},'a'*64,self.now+1)
        self.assertNotIn('limits',disabled)

    def test_secret_generation_change_discards_external_backoff_and_old_account(self):
        self.run_reader(self.now)
        (self.root/'connections.sealed').write_bytes(b'synthetic-generation')
        value,calls=self.run_reader(self.now+1)
        self.assertEqual(calls,1);self.assertEqual(value['limits_at'],self.now+1)


if __name__=='__main__':unittest.main()
