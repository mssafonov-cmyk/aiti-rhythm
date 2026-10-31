import json
from pathlib import Path
import tempfile
import time
import unittest
from session_navigation import codex_navigation, destination, notification_target, activate, valid_activation_args

SID='00000000-0000-0000-0000-000000000001'
OTHER='00000000-0000-0000-0000-000000000002'


class NavigationTests(unittest.TestCase):
    def test_protocol_cannot_inject_worker_flags(self):
        self.assertTrue(valid_activation_args(['--notification','aiti-rhythm://notification/'+SID]))
        for args in (['--notification','uri','--collector'],['--collector','--notification','uri'],['--notification','uri','--data-dir','elsewhere']):
            self.assertFalse(valid_activation_args(args))

    def test_latest_rollout_origin_reaches_collector(self):
        import os
        from datetime import datetime,timezone
        from local_metrics import codex_local
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);(root/'sessions').mkdir();now=time.time()
            for name,origin,age in [('old','Codex Desktop',1),('new','VS Code',0)]:
                p=root/'sessions'/(name+'.jsonl');stamp=datetime.now(timezone.utc).isoformat()
                records=[dict(type='session_meta',timestamp=stamp,payload=dict(id=SID,cwd=str(root),originator=origin,source='vscode')),
                         dict(type='event_msg',timestamp=stamp,payload=dict(type='task_started'))]
                p.write_text('\n'.join(json.dumps(r) for r in records)+'\n');os.utime(p,(now-age,now-age))
            self.assertEqual(codex_local(root)['sessions'][0]['navigation']['kind'],'codex_vscode')

    def test_desktop_is_not_mistaken_for_vscode(self):
        self.assertEqual(codex_navigation(dict(originator='Codex Desktop',source='vscode'))['kind'],'codex_desktop')
        self.assertEqual(codex_navigation(dict(originator='VS Code',source='vscode'))['kind'],'codex_vscode')
        self.assertEqual(codex_navigation(dict(source='vscode'))['kind'],'manual')
        self.assertEqual(codex_navigation(dict(originator='codex_cli_rs',source='cli'))['kind'],'manual')

    def test_destinations_and_parent_are_explicit(self):
        expected={'codex_desktop':'codex://threads/','codex_vscode':'vscode://openai.chatgpt/local/',
                  'codex_cursor':'cursor://openai.chatgpt/local/','codex_windsurf':'windsurf://openai.chatgpt/local/'}
        for kind,prefix in expected.items():
            self.assertEqual(destination(dict(provider='Codex',id=SID,navigation=dict(kind=kind))),prefix+SID)
        nav=codex_navigation(dict(originator='Codex Desktop',source={'subagent':{'thread_spawn':{'parent_thread_id':OTHER}}}))
        self.assertEqual(destination(dict(provider='Codex',id=SID,navigation=nav)),'codex://threads/'+OTHER)
        self.assertEqual(destination(dict(provider='Claude',id=SID,navigation={'kind':'claude_vscode'})),
                         'vscode://anthropic.claude-code/open?session='+SID)

    def test_untrusted_destinations_do_not_execute_commands(self):
        for target in ({'id':SID,'url':'https://example.com','command':'calc.exe'},
                       {'id':'../../file','navigation':{'kind':'codex_desktop'}},
                       {'provider':'Claude','id':SID,'navigation':{'kind':'codex_desktop'}},
                       {'id':SID,'navigation':{'kind':'cmd.exe'}}):
            self.assertIsNone(destination(target))

    def test_immutable_reference_activation_expiry_and_unknown_fallback(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);(root/'notifications').mkdir();p=root/'notifications'/(OTHER+'.json')
            uri='aiti-rhythm://notification/'+OTHER
            target=dict(provider='Codex',id=SID,navigation={'kind':'codex_desktop'})
            p.write_text(json.dumps(dict(at=time.time(),target=target)))
            opened=[];self.assertTrue(activate(root,uri,opened.append));self.assertEqual(opened,['codex://threads/'+SID])
            self.assertEqual(notification_target(root,uri)['id'],SID)
            for invalid in (uri+'?url=calc.exe',uri+'#payload','https://notification/'+OTHER,'aiti-rhythm://notification/../../file'):
                with self.assertRaises((ValueError,FileNotFoundError)):notification_target(root,invalid)
            p.write_text(json.dumps(dict(at=time.time()-86401,target=target)))
            with self.assertRaises(ValueError):notification_target(root,uri)
            target['navigation']={'kind':'manual'};p.write_text(json.dumps(dict(at=time.time(),target=target)))
            self.assertFalse(activate(root,uri,opened.append))
            self.assertEqual(json.loads((root/'notification-open.signal').read_text())['id'],SID)


if __name__=='__main__':unittest.main()
