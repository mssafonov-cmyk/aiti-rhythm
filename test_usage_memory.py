import json
from pathlib import Path
import tempfile
import unittest
import time
import copy
from unittest.mock import patch
from burn import day_start_msk
from usage_metrics import DailyUsageMemory, combined_usage
from collector_service import Collector
from runtime import DEFAULTS


class DailyMemoryTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name); self.now = 1793451600
        self.ids = {'claude': 'a'*64}

    def sample(self, total=120, at=None, **extra):
        return {'claude': dict(enabled=True, checked_at=self.now if at is None else at,
                               observed=True, tokens=dict(input=total, output=0),
                               burn=dict(per_min=8, series=[], leaders=[]), **extra)}

    def provider(self, snapshot, now=None):
        return next(p for p in combined_usage(snapshot, self.now if now is None else now)['providers'] if p['key']=='claude')

    def test_error_stale_restart_and_recovery_keep_daily_not_old_rate(self):
        memory = DailyUsageMemory(self.root)
        memory.enrich(self.sample(), self.ids, self.now)
        failed = self.sample(error='TimeoutError')
        failed['claude']['sessions']=[{'title':'PRIVATE_MESSAGE'}]
        held = memory.enrich(failed, self.ids, self.now+1)
        p = self.provider(held, self.now+1)
        self.assertEqual(p['day_tokens'],120); self.assertTrue(p['cached_day'])
        self.assertIsNone(p['per_min']); self.assertEqual(p['series'],[])
        self.assertNotIn('PRIVATE_MESSAGE',memory.path.read_text())
        restarted = DailyUsageMemory(self.root)
        p = self.provider(restarted.enrich({'claude':{'enabled':True}},self.ids,self.now+2),self.now+2)
        self.assertEqual(p['day_tokens'],120)
        p = self.provider(memory.enrich(self.sample(),self.ids,self.now+181),self.now+181)
        self.assertTrue(p['cached_day']);self.assertIsNone(p['per_min'])
        recovered = self.provider(memory.enrich(self.sample(150,at=self.now+182),self.ids,self.now+182),self.now+182)
        self.assertEqual(recovered['day_tokens'],150);self.assertFalse(recovered['cached_day'])

    def test_regression_or_empty_sample_never_erases_high_water_mark(self):
        m=DailyUsageMemory(self.root);m.enrich(self.sample(120),self.ids,self.now)
        for total in (0,90):
            p=self.provider(m.enrich(self.sample(total,at=self.now+1),self.ids,self.now+1),self.now+1)
            self.assertEqual(p['day_tokens'],120);self.assertTrue(p['cached_day'])
        self.assertFalse(self.provider(m.enrich(self.sample(120,at=self.now+2),self.ids,self.now+2),self.now+2)['cached_day'])

    def test_day_profile_and_disable_boundaries(self):
        m=DailyUsageMemory(self.root);m.enrich(self.sample(),self.ids,self.now)
        changed=m.enrich({'claude':{'enabled':True}}, {'claude':'b'*64},self.now+1)
        self.assertIsNone(self.provider(changed,self.now+1)['day_tokens'])
        m.enrich(self.sample(),self.ids,self.now)
        disabled=m.enrich({'claude':{'enabled':False}},self.ids,self.now+1)
        self.assertNotIn('Claude',[p['name'] for p in combined_usage(disabled,self.now+1)['providers']])
        tomorrow=day_start_msk(self.now)+86400+1
        old=m.enrich(self.sample(),self.ids,tomorrow)
        self.assertIsNone(self.provider(old,tomorrow)['day_tokens'])
        self.assertFalse(m.entries)

    def test_cross_midnight_request_and_unknown_are_not_new_day_totals(self):
        m=DailyUsageMemory(self.root);m.enrich(self.sample(),self.ids,self.now)
        tomorrow=day_start_msk(self.now)+86400+5
        crossed=self.sample(at=tomorrow,usage_day=day_start_msk(self.now))
        self.assertIsNone(self.provider(m.enrich(crossed,self.ids,tomorrow),tomorrow)['day_tokens'])
        self.assertFalse(m.entries)

    def test_corrupt_file_and_write_failure_still_work_in_ram(self):
        (self.root/'daily-token-totals.json').write_text('invalid')
        m=DailyUsageMemory(self.root)
        with patch('usage_metrics.atomic_json',side_effect=OSError):
            m.enrich(self.sample(),self.ids,self.now)
            self.assertEqual(self.provider(m.enrich(self.sample(error='IOError'),self.ids,self.now+1),self.now+1)['day_tokens'],120)

    def test_known_zero_cache_is_stale_not_a_current_zero_rate(self):
        m=DailyUsageMemory(self.root);m.enrich(self.sample(0),self.ids,self.now)
        snap=m.enrich(self.sample(error='TimeoutError'),self.ids,self.now+1)
        p=self.provider(snap,self.now+1)
        self.assertEqual(p['day_tokens'],0);self.assertTrue(p['cached_day'])
        self.assertIsNone(p['per_min']);self.assertTrue(combined_usage(snap,self.now+1)['partial'])

    def test_collector_failure_restart_and_profile_change(self):
        settings=copy.deepcopy(DEFAULTS)
        for name in ('codex','antigravity','calendar','cube'):settings[name]['enabled']=False
        settings['claude']['home']='profile-a'
        path=self.root/'connections.json';path.write_text(json.dumps(settings))
        now=time.time();collector=Collector(self.root)
        try:
            value=self.sample(at=now)['claude']
            with patch.object(collector,'work',return_value=value):
                collector.step(now)
                for _,future in collector.pending.values():future.result(timeout=2)
                first=collector.step(now+0.1)
                self.assertEqual(self.provider(first,now+0.1)['day_tokens'],120)
            with patch.object(collector,'work',side_effect=TimeoutError):
                collector.step(now+16)
                for _,future in collector.pending.values():
                    try:future.result(timeout=2)
                    except TimeoutError:pass
                failed=collector.step(now+16.1)
                self.assertTrue(self.provider(failed,now+16.1)['cached_day'])
        finally:collector.close()
        restarted=Collector(self.root)
        try:
            with patch.object(restarted,'work',side_effect=TimeoutError):
                held=restarted.step(now+17)
                self.assertEqual(self.provider(held,now+17)['day_tokens'],120)
                settings['claude']['home']='profile-b';path.write_text(json.dumps(settings))
                switched=restarted.step(now+18)
                self.assertIsNone(self.provider(switched,now+18)['day_tokens'])
        finally:restarted.close()


if __name__=='__main__':unittest.main()
