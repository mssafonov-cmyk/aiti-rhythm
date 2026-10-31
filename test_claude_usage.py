import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import urllib.request
from claude_usage import normalize_usage, cached_usage, preserve_reset_metadata, with_reset_metadata_source
from runtime import save_connection, load_settings, load_secrets


class QuotaMetadataTests(unittest.TestCase):
    def test_existing_remote_program_retains_metadata_in_its_single_request(self):
        source='''import json, urllib.request
with urllib.request.urlopen('https://api.anthropic.com/api/oauth/usage') as response:
    data=json.load(response)
limits={'seven_day':{'used_percentage':data['seven_day']['utilization']}}
print(json.dumps({'limits':limits,'limits_at':123}))
'''
        payload={'seven_day':{'utilization':17,'resets_at':'2026-11-07T09:00:00Z'}}
        with patch('urllib.request.urlopen',return_value=io.BytesIO(json.dumps(payload).encode())) as request:
            with patch('sys.stdout',new_callable=io.StringIO) as output:
                exec(with_reset_metadata_source(source),{})
            request.assert_called_once()
        result=json.loads(output.getvalue())
        self.assertEqual(result['limits']['seven_day']['resets_at'],'2026-11-07T09:00:00+00:00')
        self.assertEqual(with_reset_metadata_source("print('unrelated')"),"print('unrelated')")

    def test_windows_are_independent_and_unknown_reset_is_not_invented(self):
        values=normalize_usage({'five_hour':{'utilization':0,'resets_at':None},
            'seven_day':{'utilization':17,'resets_at':'2026-11-04T09:00:00Z'}})
        self.assertEqual(values['five_hour'],{'used_percentage':0})
        self.assertEqual(values['seven_day']['used_percentage'],17)
        self.assertEqual(values['seven_day']['resets_at'],'2026-11-04T09:00:00+00:00')
        self.assertNotIn('resets_at',normalize_usage({'five_hour':{'utilization':20,'resets_at':'2026-11-04T09:00:00'}})['five_hour'])

    def test_existing_request_keeps_reset_metadata_without_extra_requests(self):
        payload={'five_hour':{'utilization':20,'resets_at':'2026-11-01T09:00:00Z'}}
        def legacy():
            with urllib.request.urlopen('https://api.anthropic.com/api/oauth/usage') as response:
                body=json.load(response)
            return {'limits':{'five_hour':{'used_percentage':body['five_hour']['utilization']}}}
        with patch('urllib.request.urlopen',return_value=io.BytesIO(json.dumps(payload).encode())) as request:
            result=preserve_reset_metadata(legacy)
            self.assertIs(urllib.request.urlopen,request)
            request.assert_called_once()
        self.assertEqual(result['limits']['five_hour']['resets_at'],'2026-11-01T09:00:00+00:00')

    def test_failed_request_restores_hook_and_mismatched_sample_is_not_merged(self):
        with patch('urllib.request.urlopen',side_effect=OSError) as request:
            with self.assertRaises(OSError):
                preserve_reset_metadata(lambda:urllib.request.urlopen('https://api.anthropic.com/api/oauth/usage'))
            self.assertIs(urllib.request.urlopen,request)
        def stale():
            with urllib.request.urlopen('https://api.anthropic.com/api/oauth/usage') as response:
                response.read()
            return {'limits':{'five_hour':{'used_percentage':40}}}
        payload={'five_hour':{'utilization':20,'resets_at':'2026-11-01T09:00:00Z'}}
        with patch('urllib.request.urlopen',return_value=io.BytesIO(json.dumps(payload).encode())):
            self.assertNotIn('resets_at',preserve_reset_metadata(stale)['limits']['five_hour'])

    def test_custom_profile_does_not_fall_back_to_another_accounts_cache(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            (root/'.claude.json').write_text(json.dumps({'cachedUsageUtilization':{'fetchedAtMs':1000,
                'utilization':{'five_hour':{'utilization':12}}}}))
            self.assertEqual(cached_usage(root/'.claude')[0]['five_hour']['used_percentage'],12)
            self.assertEqual(cached_usage(root/'custom-profile'),({},None))

    def test_hiding_blocks_preserves_connections_and_encrypted_secret_file(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            save_connection({'calendar':{'enabled':True},'secrets':{'calendar_url':'synthetic-calendar',
                'claude_command':['reader.exe','--json']}},root)
            before=(root/'connections.sealed').read_bytes()
            save_connection({'view':{'calendar':False,'sessions':False,'auto_height':True}},root)
            self.assertTrue(load_settings(root)['calendar']['enabled'])
            self.assertFalse(load_settings(root)['view']['calendar'])
            self.assertEqual((root/'connections.sealed').read_bytes(),before)
            self.assertEqual(load_secrets(root)['calendar_url'],'synthetic-calendar')
