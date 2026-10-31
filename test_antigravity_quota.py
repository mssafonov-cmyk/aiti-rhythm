import copy
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
from antigravity_quota import capture, read_quota, manage, paths, load_state, sync_capture, remove_all
from runtime import DEFAULTS


class QuotaTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.root=Path(self.tmp.name)/'Личные данные';self.root.mkdir()
        self.home=Path(self.tmp.name)/'Профиль & тест';self.home.mkdir()
        self.now=1793451600

    def payload(self):
        return dict(email='PRIVATE_EMAIL',conversation_title='PRIVATE_TITLE',quota={
            'gemini-weekly':dict(remaining_fraction=0.75,reset_in_seconds=86400,secret='PRIVATE_TOKEN'),
            'gemini-5h':dict(remaining_fraction=0,reset_time='2026-11-01T10:00:00Z'),
            '3p-weekly':dict(remaining_fraction=0.4,reset_in_seconds=86400),
            'unknown-private-bucket':dict(remaining_fraction=0.9)})

    def test_whitelist_real_zero_profile_age_reset_and_missing(self):
        self.assertTrue(capture(self.payload(),self.root,self.home,self.now))
        text=paths(self.root,self.home)[2].read_text()
        self.assertNotIn('PRIVATE',text);self.assertNotIn('unknown',text)
        result=read_quota(self.root,self.home,self.now)
        self.assertEqual(result['quota']['gemini-5h']['remaining_fraction'],0)
        self.assertFalse(result['quota']['gemini-weekly']['stale'])
        self.assertTrue(read_quota(self.root,self.home,self.now+601)['quota']['gemini-weekly']['stale'])
        self.assertFalse(read_quota(self.root,self.home,self.now+86401))
        self.assertFalse(read_quota(self.root,self.home/'another',self.now))
        before=paths(self.root,self.home)[2].read_bytes()
        self.assertFalse(capture({'context_window':{}},self.root,self.home,self.now+2))
        self.assertEqual(before,paths(self.root,self.home)[2].read_bytes())
        capture({'quota':{'gemini-weekly':dict(remaining_fraction=1,reset_in_seconds=1)}},self.root,self.home,self.now)
        self.assertFalse(read_quota(self.root,self.home,self.now+2))

    def test_opt_in_restore_unknown_settings_and_protected_original(self):
        original=dict(colorScheme='terminal',futureSetting={'keep':True},statusLine=dict(command='echo PRIVATE_COMMAND',padding=2))
        config=self.home/'settings.json';config.write_text(json.dumps(original))
        command=[sys.executable,str(Path(__file__).with_name('rhythm_app.py'))]
        manage(self.root,self.home,True,command)
        state,wrapper,_=paths(self.root,self.home)
        self.assertNotIn(b'PRIVATE_COMMAND',state.read_bytes())
        self.assertTrue(wrapper.read_text().isascii())
        self.assertEqual(json.loads(config.read_text())['futureSetting'],{'keep':True})
        manage(self.root,self.home,True,command)
        self.assertEqual(load_state(state)['original'],original['statusLine'])
        manage(self.root,self.home,False,command)
        self.assertEqual(json.loads(config.read_text()),original)
        self.assertFalse(load_state(state)['active'])

    def test_native_callback_preserves_bytes_and_never_saves_payload(self):
        original=Path(self.tmp.name)/'original source.py'
        original.write_text('import sys;sys.stdout.buffer.write(sys.stdin.buffer.read())')
        cmd=subprocess.list2cmdline([sys.executable,str(original)])
        (self.home/'settings.json').write_text(json.dumps(dict(statusLine=dict(command=cmd))))
        manage(self.root,self.home,True,[sys.executable,str(Path(__file__).with_name('rhythm_app.py'))])
        wrapper=paths(self.root,self.home)[1]
        shell=str(Path(os.environ['SystemRoot'])/'System32/cmd.exe')
        payload=self.payload()
        payload['quota']['gemini-5h']=dict(remaining_fraction=0,reset_in_seconds=18000)
        raw=json.dumps(payload,ensure_ascii=False).encode('utf-8')
        native_command=json.loads((self.home/'settings.json').read_text())['statusLine']['command']
        result=subprocess.run([shell,'/c',native_command],input=raw,capture_output=True,timeout=20)
        self.assertEqual(result.returncode,0,result.stderr.decode(errors='replace'))
        self.assertEqual(result.stdout,raw)
        self.assertEqual(len(read_quota(self.root,self.home)['quota']),3)
        self.assertNotIn('PRIVATE',paths(self.root,self.home)[2].read_text())

    def test_disable_does_not_overwrite_user_replacement_and_rollback(self):
        config=self.home/'settings.json';original=dict(statusLine=dict(command='echo original'),keep=123)
        config.write_text(json.dumps(original));undo=manage(self.root,self.home,True,['core.exe'])
        undo();self.assertEqual(json.loads(config.read_text()),original)
        manage(self.root,self.home,True,['core.exe'])
        edited=dict(original,statusLine=dict(command='echo user-new'));config.write_text(json.dumps(edited))
        manage(self.root,self.home,False,['core.exe'])
        self.assertEqual(json.loads(config.read_text()),edited)

    def test_profile_switch_and_uninstall_restore_only_managed_lines(self):
        previous=copy.deepcopy(DEFAULTS);desired=copy.deepcopy(DEFAULTS)
        previous['antigravity'].update(home=str(self.home),capture_quota=True)
        desired['antigravity'].update(home=str(self.home/'new'),capture_quota=True)
        manage(self.root,self.home,True,['core.exe'])
        sync_capture(previous,desired,self.root,['core.exe'])
        self.assertFalse((self.home/'settings.json').exists())
        self.assertTrue((self.home/'new/settings.json').exists())
        remove_all(self.root)
        self.assertFalse((self.home/'new/settings.json').exists())


if __name__=='__main__':unittest.main()
