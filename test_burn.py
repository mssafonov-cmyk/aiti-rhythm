import unittest
from burn import velocity,day_series,day_start_msk

class BurnTests(unittest.TestCase):
    def test_no_false_baseline_without_history(self):
        r=velocity([(999,1000000,10000)],1000)
        self.assertEqual(r['level'],'learning')
        self.assertIsNone(r['ratio'])
        self.assertEqual(r['per_min'],66667)

    def test_spike_against_active_windows(self):
        now=day_start_msk(100000)+12*3600
        points=[(now-1800-i*900,300000,30000) for i in range(4)]
        points.append((now-1,1500000,75000))
        r=velocity(points,now)
        self.assertEqual(r['baseline_per_min'],20000)
        self.assertEqual(r['ratio'],5)
        self.assertEqual(r['level'],'critical')
        self.assertEqual(r['uncached_per_min'],5000)

    def test_old_future_and_small_volume_not_alerts(self):
        now=day_start_msk(100000)+12*3600
        points=[(now-1800-i*900,3000,3000) for i in range(4)]
        points.extend([(now-1,30000,30000),(now+10,9000000,0),(day_start_msk(now)-1,9000000,0)])
        r=velocity(points,now)
        self.assertEqual(r['per_min'],2000)
        self.assertEqual(r['level'],'normal')

    def test_idle_not_learning_and_window_change(self):
        now=day_start_msk(100000)+12*3600
        points=[(now-1000,300000,0)]
        self.assertEqual(velocity(points,now)['level'],'idle')
        self.assertEqual(velocity(points,now,1800)['per_min'],10000)

    def test_day_chart_marks_anomaly_without_future_baseline(self):
        now=day_start_msk(100000)+12*3600
        start=day_start_msk(now)
        points=[(start+i*900+1,300000,0) for i in range(3)]
        points.append((start+2701,1500000,0))
        bars=day_series(points,now)
        self.assertEqual(bars[0]['level'],'learning')
        self.assertEqual(bars[3]['level'],'critical')
        self.assertEqual(bars[-1]['level'],'partial')

if __name__=='__main__':unittest.main()
