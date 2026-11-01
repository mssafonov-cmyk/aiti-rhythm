"""Portable read-only local Codex metrics. No credentials, network or model calls."""
import json, time
from pathlib import Path
from datetime import datetime, timedelta, timezone
from burn import velocity, day_series
MSK=timezone(timedelta(hours=3))
from app_paths import DATA as HERE
from codex_account import account_fingerprint, owner_fingerprint

def stamp(value):
    dt=datetime.fromisoformat(value.replace('Z','+00:00'))
    return dt.replace(tzinfo=MSK) if dt.tzinfo is None else dt

def records(path):
    with path.open(encoding='utf-8') as stream:
        for line in stream:
            try:yield json.loads(line)
            except ValueError:continue

_session_cache = {}

def session_records(path):
    """Read only appended complete lines, bounded by size at poll start."""
    stat = path.stat()
    signature = (stat.st_dev, stat.st_ino)
    entry = _session_cache.get(path)
    if (entry is None or entry['identity'] != signature or
            stat.st_size < entry['offset'] or
            (stat.st_size == entry['size'] and stat.st_mtime_ns != entry['mtime'])):
        entry = dict(identity=signature, offset=0, size=0, mtime=0, rows=[])
        _session_cache[path] = entry
    with path.open('rb') as stream:
        stream.seek(entry['offset'])
        while stream.tell() < stat.st_size:
            raw = stream.readline(stat.st_size-stream.tell())
            if not raw.endswith(b'\n'):
                break
            try: row = json.loads(raw)
            except (ValueError, UnicodeDecodeError):
                if not raw.endswith(b'\n'): break
                entry['offset'] = stream.tell()
                continue
            entry['offset'] = stream.tell()
            kind = row.get('type')
            payload = row.get('payload', {})
            if kind == 'session_meta' or (kind == 'event_msg' and payload.get('type') in
                    ('task_started','task_complete','turn_aborted','task_interrupted','token_count')):
                entry['rows'].append(row)
            elif kind == 'response_item':
                # Keep only status metadata, never tool output or message bodies.
                entry['rows'].append(dict(type=kind, timestamp=row.get('timestamp'),
                    payload={k:payload[k] for k in ('type','role','name','call_id','id') if k in payload}))
    entry.update(size=stat.st_size, mtime=stat.st_mtime_ns)
    return entry['rows']

class SessionState:
    def __init__(self):
        self.status='unknown';self.at=0;self.activity_at=0;self.pending={}
    def consume(self,r,dt):
        p=r.get('payload',{});kind=p.get('type')
        if r.get('type') in ('response_item','event_msg'):
            self.activity_at=max(self.activity_at,dt.timestamp())
        if r.get('type')=='response_item':
            if p.get('role')=='user':self.pending.clear()
            name=p.get('name','')
            if kind in ('function_call','custom_tool_call') and name.endswith(('request_user_input','request_user_input_async')):
                self.pending[p.get('call_id',p.get('id','input'))]=name
                if not name.endswith('_async'):self.status='waiting';self.at=dt.timestamp()
            elif kind in ('function_call_output','custom_tool_call_output'):
                call=p.get('call_id');name=self.pending.get(call,'')
                if name and not name.endswith('_async'):
                    self.pending.pop(call);self.status='working';self.at=dt.timestamp()
        if r.get('type')=='event_msg':
            if kind=='task_started':self.status='working';self.at=dt.timestamp();self.pending.clear()
            elif kind=='task_complete':self.status='waiting' if self.pending else 'idle';self.at=dt.timestamp()
            elif kind in ('turn_aborted','task_interrupted'):self.status='interrupted';self.at=dt.timestamp();self.pending.clear()

def codex_local(home=None):
    """Daily cumulative deltas; repeated token_count snapshots are not double counted."""
    now = datetime.now(MSK); day = now.date()
    window=900
    try:
        options=json.loads((HERE/'metric-options.json').read_text(encoding='utf-8-sig'))
        minutes=int(options.get('window_minutes',15))
        if minutes in (15,30,60):window=minutes*60
    except (OSError,ValueError,TypeError):pass
    totals = dict(input=0, output=0, cache=0)
    sessions = []; observed = False; consumers=[];all_points=[]
    source_home=Path(home) if home is not None else Path.home()/'.codex'
    current_account=account_fingerprint(source_home); excluded_sessions=0;recent_other_sessions=0
    index=source_home/'session_index.jsonl'
    titles={r.get('id'):r.get('thread_name','') for r in records(index)} if index.exists() else {}
    from session_navigation import codex_navigation
    samples = {}
    for p in (source_home/'sessions').rglob('*.jsonl'):
        if p.stat().st_mtime < now.timestamp()-7*86400: continue
        prev = {}; state = 'unknown'; last = 0; project = ''; sid = str(p);navigation={'kind':'manual'};owner=None
        sums = dict(input=0,output=0,cache=0);points=[];status=SessionState()
        for r in session_records(p):
            try: payload=r.get('payload',{}); dt=stamp(r['timestamp']).astimezone(MSK)
            except (ValueError,KeyError): continue
            status.consume(r,dt)
            if r.get('type')=='session_meta':
                sid=payload.get('id',sid); project=Path(payload.get('cwd','')).name
                navigation=codex_navigation(payload)
                owner=owner_fingerprint(payload.get('creator_account_id'))
                # Fork histories can contain parent totals: never charge their initial snapshot.
                if payload.get('forked_from_id'): prev={'_fork':True}
            if r.get('type')!='event_msg': continue
            typ=payload.get('type')
            if typ=='task_started': state='working'; last=dt.timestamp()
            elif typ in ('task_complete','turn_aborted','task_interrupted'): state='idle'; last=dt.timestamp()
            if typ!='token_count': continue
            usage=(payload.get('info') or {}).get('total_token_usage') or {}
            if not usage: continue
            if prev and not prev.get('_fork') and dt.date()==day and dt.timestamp()<=now.timestamp():
                inp=max(0,usage.get('input_tokens',0)-prev.get('input_tokens',0))
                out=max(0,usage.get('output_tokens',0)-prev.get('output_tokens',0))
                cache=max(0,usage.get('cached_input_tokens',0)-prev.get('cached_input_tokens',0))
                if inp+out:points.append((dt.timestamp(),inp+out,max(0,inp-cache)+out))
            if dt.date()==day and dt.timestamp()<=now.timestamp():
                observed=True
                for dst,src in [('input','input_tokens'),('output','output_tokens'),('cache','cached_input_tokens')]:
                    delta=max(0,usage.get(src,0)-prev.get(src,0)) if not prev.get('_fork') else 0
                    sums[dst]+=delta
            prev=usage
        # A thread can have multiple retained journals. File-copy time and traversal
        # order are not evidence of current activity; take the newest event stream.
        rank=(status.activity_at,p.stat().st_mtime)
        previous=samples.get(sid)
        if previous:
            # A resumed/cropped copy can have a smaller counter history. Updating
            # status must not erase spend already present in the complete copy.
            if sum(previous['sums'][k] for k in ('input','output'))>sum(sums[k] for k in ('input','output')):
                points=previous['points']
            sums={key:max(sums[key],previous['sums'][key]) for key in sums}
        if sid not in samples or rank>samples[sid]['rank']:
            samples[sid]=dict(rank=rank,navigation=navigation,owner=owner,project=project,
                              sums=sums,points=points,status=status)
        else:
            previous.update(sums=sums,points=points)
    for sid,sample in samples.items():
        navigation=sample['navigation'];owner=sample['owner'];project=sample['project']
        sums=sample['sums'];points=sample['points'];status=sample['status']
        all_points.extend(points)
        rate=velocity(points,now.timestamp(),window)
        if sums['input']+sums['output']:
            consumers.append(dict(id=sid,title=titles.get(sid,project),project=project,navigation=navigation,
                                  day_tokens=sums['input']+sums['output'],**rate))
        for k in totals: totals[k]+=sums[k]
        state=status.status;last=status.activity_at or status.at
        recent=0<=time.time()-last<=1800
        if state=='working' and not recent:state='unknown'
        if last>=now.replace(hour=0,minute=0,second=0,microsecond=0).timestamp() or state in ('working','waiting'):
            # creator_account_id is immutable when a chat is resumed after login
            # changes. Never discard actual work just because its creator differs.
            resumed=recent and state in ('working','waiting','idle','interrupted')
            if current_account and owner != current_account and not resumed:
                excluded_sessions+=1
                continue
            if current_account and owner != current_account:recent_other_sessions+=1
            sessions.append(dict(provider='Codex',project=project,status=state,at=last,
                                 id=sid,title=titles.get(sid,project),rate=rate,navigation=navigation))
    consumers.sort(key=lambda v:(v['per_min'],v['day_tokens']),reverse=True)
    overall=velocity(all_points,now.timestamp(),window)
    overall['alert']=overall['level'] in ('warning','critical') or any(v['level'] in ('warning','critical') for v in consumers)
    overall['series']=day_series(all_points,now.timestamp())
    overall['leader_basis']='window' if overall['per_min'] else 'day'
    if overall['per_min']==0:consumers.sort(key=lambda v:v['day_tokens'],reverse=True)
    # Journal ownership is not proof of which subscription paid for each turn.
    # Tokens/history deliberately remain profile-wide and are labelled as such in UI.
    return dict(tokens=totals,observed=observed,sessions=sessions,checked_at=time.time(),
                session_scope='live_and_account_history' if current_account else 'profile', excluded_sessions=excluded_sessions,
                recent_other_account_sessions=recent_other_sessions,
                account_fingerprint=current_account, token_scope='profile',
                burn=dict(**overall,leaders=consumers[:10]))
