"""Local token volume, including cache. Not a money or quota-cost estimate."""
from statistics import median

def day_start_msk(now):
    return int((now+10800)//86400)*86400-10800

def classify(rate, baseline):
    if rate==0:return 'idle'
    if baseline is None:return 'learning'
    ratio=rate/baseline if baseline else 0
    if ratio>=4 and rate>=100000:return 'critical'
    if ratio>=2 and rate>=50000:return 'warning'
    if ratio<0.7:return 'below'
    return 'normal'

def velocity(points, now, window_seconds=900):
    """Rolling 15/30/60m vs completed active windows of equal length today."""
    if window_seconds not in (900,1800,3600):window_seconds=900
    start=day_start_msk(now)
    points=[p for p in points if start<=p[0]<=now]
    current=[p for p in points if now-p[0]<window_seconds]
    buckets={}
    for at,total,uncached in points:
        idx=int((at-start)//window_seconds)
        buckets[idx]=buckets.get(idx,0)+total
    active=[v/(window_seconds/60) for idx,v in buckets.items()
            if v>0 and start+(idx+1)*window_seconds<=now-window_seconds]
    baseline=median(active) if len(active)>=3 else None
    rate=sum(p[1] for p in current)/(window_seconds/60)
    uncached=sum(p[2] for p in current)/(window_seconds/60)
    ratio=rate/baseline if baseline else None
    return dict(per_min=round(rate),uncached_per_min=round(uncached),
                baseline_per_min=round(baseline) if baseline is not None else None,
                ratio=round(ratio,1) if ratio is not None else None,
                level=classify(rate,baseline),baseline_windows=len(active),
                window_seconds=window_seconds,last_activity=max((p[0] for p in points),default=None))

def day_series(points,now):
    """15m bars; compare only earlier completed bars, never future data."""
    start=day_start_msk(now);values={}
    for at,total,_ in points:
        if start<=at<=now:
            idx=int((at-start)//900);values[idx]=values.get(idx,0)+total
    out=[];history=[]
    for idx in range(int((now-start)//900)+1):
        value=values.get(idx,0);rate=value/15
        baseline=median(history) if len(history)>=3 else None
        complete=start+(idx+1)*900<=now
        level=classify(rate,baseline) if complete else 'partial'
        out.append(dict(at=start+idx*900,tokens=value,per_min=round(rate),level=level,complete=complete))
        if complete and value:history.append(rate)
    return out
