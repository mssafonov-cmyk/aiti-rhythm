"""Prism dashboard: high-contrast watchface layouts, supersampled vector artwork.

Design references: codelight dark screen and LVGL smartwatch glance hierarchy.
No external art copied; all icons are drawn here, real measurements only.
"""
import time
from datetime import datetime, timedelta, timezone
from PIL import Image, ImageDraw, ImageFont


S=3
BG='#080F1C'; PANEL='#132135'; INK='#F1F6FF'; MUTED='#A4B4C9'
CYAN='#61D8FF'; CORAL='#FF9A78'; MINT='#73EDBA'; PURPLE='#BBABFF'; GOLD='#FFD374'; RED='#FF7F87'
FONTS={False:r'C:\Windows\Fonts\segoeui.ttf',True:r'C:\Windows\Fonts\segoeuib.ttf','num':r'C:\Windows\Fonts\bahnschrift.ttf'}
def stamp(value):
    dt = datetime.fromisoformat(value.replace('Z', '+00:00'))
    return dt.replace(tzinfo=timezone(timedelta(hours=3))) if dt.tzinfo is None else dt


def age(data, key='checked_at'):
    return max(0, time.time() - (data.get(key) or 0))


def fresh(data, seconds=600):
    return bool(data) and not data.get('error') and age(data) < seconds


def next_event(calendar, now=None):
    now = time.time() if now is None else now
    for event in calendar.get('events', []):
        if event.get('all_day'):
            continue
        start = stamp(event['planned_date']).timestamp()
        if start + 300 >= now:
            return event, start
    return None, None


def calendar_fresh(calendar):
    if not fresh(calendar, 180):
        return False
    synced = calendar.get('synced_at')
    return not synced or time.time() - stamp(synced).timestamp() < 900


def compact(n):
    if n>=1e6:return f'{n/1e6:.1f}M'
    if n>=1e3:return f'{n/1e3:.1f}K'
    return str(n)

class Canvas:
    def __init__(self,title,accent,page,icon):
        self.im=Image.new('RGB',(240*S,240*S),BG);self.d=ImageDraw.Draw(self.im);self.accent=accent
        # Restrained corner lighting, no full-screen saturated fill.
        rgb=tuple(int(accent[i:i+2],16) for i in (1,3,5))
        for y in range(240*S):
            a=.065*max(0,1-y/(170*S))
            col=tuple(round(v*(1-a)+r*a) for v,r in zip((8,15,28),rgb))
            self.d.line((0,y,240*S,y),fill=col)
        self.text(16,12,title,19,INK,True)
        self.icon(icon,207,16,18,accent)
        self.line((16,40,224,40),'#233249',.65)
        for n in range(4):
            x=98+n*13
            self.round((x,229,x+(8 if n==page else 4),232),2,accent if n==page else '#3E4C60')
    def font(self,size,bold=False):return ImageFont.truetype(FONTS[bold],round(size*S))
    def text(self,x,y,value,size=14,color=INK,bold=False,anchor='lt'):
        self.d.text((x*S,y*S),str(value),font=self.font(size,bold),fill=color,anchor=anchor)
    def width(self,value,size,bold=False):return self.d.textlength(str(value),font=self.font(size,bold))/S
    def line(self,box,color,width=1):self.d.line(tuple(round(v*S) for v in box),fill=color,width=max(1,round(width*S)))
    def round(self,box,r,color,outline=None,width=1):self.d.rounded_rectangle(tuple(round(v*S) for v in box),round(r*S),fill=color,outline=outline,width=round(width*S))
    def ellipse(self,box,color,outline=None,width=1):self.d.ellipse(tuple(round(v*S) for v in box),fill=color,outline=outline,width=round(width*S))
    def fit(self,x,y,value,maxw,maxlines=2,size=19,lineheight=None,color=INK,bold=True):
        value=str(value).replace('_',' ').strip(); words=value.split();lines=[];line=''
        for word in words:
            if self.width((line+' '+word).strip(),size,bold)>maxw and line:lines.append(line);line=word
            else:line=(line+' '+word).strip()
        if line:lines.append(line)
        overflow=len(lines)>maxlines;lines=lines[:maxlines]
        for i,line in enumerate(lines):
            clipped=False
            while self.width(line,size,bold)>maxw and line:line=line[:-1];clipped=True
            if clipped or (overflow and i==maxlines-1):
                while self.width(line+'…',size,bold)>maxw and line:line=line[:-1]
                line=line.rstrip()+'…'
            self.text(x,y+i*(lineheight or size+4),line,size,color,bold)
    def icon(self,kind,x,y,size,color):
        # Original stroke icons, normalized to a 24-unit grid.
        q=size/24
        def l(v,w=1.8):self.line(tuple((x if i%2==0 else y)+a*q for i,a in enumerate(v)),color,w*q)
        def r(v,rad=3,fill=None):self.round((x+v[0]*q,y+v[1]*q,x+v[2]*q,y+v[3]*q),rad*q,fill,color,1.7*q)
        if kind=='calendar':
            r((3,5,21,22));l((3,10,21,10));l((8,2,8,7));l((16,2,16,7));r((7,14,10,17),.4,color)
        elif kind=='bolt':
            points=[(14,1),(5,14),(11,14),(10,23),(20,9),(13,9),(14,1)]
            self.d.polygon([(round((x+a*q)*S),round((y+b*q)*S)) for a,b in points],fill=color)
        elif kind=='chart':
            for a,h in [(3,8),(10,16),(17,12)]:r((a,23-h,a+4,23),1,color)
        elif kind=='clock':
            self.ellipse((x+2*q,y+2*q,x+22*q,y+22*q),None,color,1.8*q);l((12,6,12,12,16,15))
        elif kind=='bot':
            r((3,6,21,21),5);l((12,2,12,6));self.ellipse((x+10*q,y,x+14*q,y+4*q),color)
            for a in (8,16):self.ellipse((x+(a-1)*q,y+11*q,x+(a+1)*q,y+14*q),color)
            l((9,17,15,17));l((0,11,0,16));l((24,11,24,16))
    def ring(self,cx,cy,value,color):
        box=((cx-42)*S,(cy-42)*S,(cx+42)*S,(cy+42)*S)
        self.d.arc(box,135,405,fill='#233249',width=7*S)
        if value is not None and value>0:self.d.arc(box,135,135+270*max(0,min(100,value))/100,fill=color,width=7*S)
        self.text(cx,cy-17,'—' if value is None else str(round(value)),36,color,'num','mt')
        if value is not None:self.text(cx,cy+21,'%',16,MUTED,False,'mt')
    def finish(self):return self.im.resize((240,240),Image.Resampling.LANCZOS)

def session_label(session):
    return str(session.get('title') or session.get('project') or 'Сессия').strip() or 'Сессия'


def render_cards(data,fresh,age,next_event,calendar_fresh):
    lm=data.get('limits',{});cl=data.get('claude',{});cx=data.get('codex',{});cal=data.get('calendar',{})
    out={};good_lm=fresh(lm);good_cl=fresh(cl) and age(cl,'limits_at')<600
    cw=100*(1-lm['weekly_pct']) if good_lm and 'weekly_pct' in lm else None
    aw=cl.get('limits',{}).get('seven_day',{}).get('used_percentage') if good_cl else None
    aw=100-aw if aw is not None else None
    c=Canvas('Запас AI',CYAN,0,'bolt')
    c.text(29,49,'Codex',18,CYAN,True)
    c.text(143,49,'Claude',18,CORAL,True)
    c.ring(65,113,cw,CYAN);c.ring(175,113,aw,CORAL)
    rows=[]
    if good_lm and 'session_pct' in lm:rows.append(('Codex · 5 ч',100*(1-lm['session_pct']),CYAN))
    av=cl.get('limits',{}).get('five_hour',{}).get('used_percentage') if good_cl else None
    rows.append(('Claude · 5 ч',100-av if av is not None else None,CORAL))
    for i,(name,v,color) in enumerate(rows):
        y=168+i*24;c.text(16,y,name,16,MUTED)
        c.text(224,y,'—' if v is None else f'{round(v)}%',18,color,True,'rt')
    reset=lm.get('weekly_reset_at') if good_lm else None
    c.text(16,211,'Осталось на неделю',16,MUTED);out['limits']=c.finish()

    sessions=[s for src in (cx,cl) if fresh(src,180) for s in src.get('sessions',[])]
    waiting=[s for s in sessions if s['status']=='waiting'];working=[s for s in sessions if s['status']=='working']
    selected=sorted(waiting or working or sessions,key=lambda s:s['at'],reverse=True)
    color=RED if waiting else MINT;c=Canvas('Агенты',color,1,'bot')
    missing=not fresh(cx,180) or not fresh(cl,180)
    c.text(15,47,str(len(working)) if not missing else '—',61,color,'num')
    c.text(18,111,'в работе' if not missing else 'нет связи',19,MUTED)
    c.round((132,59,217,136),20,'#142D2B' if not waiting else '#321D2A')
    c.icon('bot',151,73,46,color)
    if selected:
        s=selected[0];c.text(16,138,s['provider'],17,color,True)
        c.fit(16,161,session_label(s),207,2,21,23)
    else:c.text(16,164,'Нет активных сессий',17,MUTED)
    c.ellipse((17,215,23,221),RED if waiting else MINT)
    c.fit(30,211,f'Ждут ответа: {len(waiting)}' if waiting else ('Часть недоступна' if missing else 'По журналам'),194,1,15,color=MUTED)
    out['agents']=c.finish()

    c=Canvas('Токены сегодня',PURPLE,2,'chart');t=cx.get('tokens',{})
    valid=fresh(cx) and cx.get('observed') and sum(t.values())>0
    c.text(16,50,'Codex · этот ПК',18,MUTED)
    total=t.get('input',0)+t.get('output',0)
    c.text(14,72,compact(total) if valid else '—',47,PURPLE,'num')
    vals=[t.get('cache',0),max(0,t.get('input',0)-t.get('cache',0)),t.get('output',0)]
    colors=[PURPLE,CYAN,CORAL];x=16
    c.round((16,149,224,157),4,PANEL)
    if valid and total:
        for v,color in zip(vals,colors):
            width=208*v/total
            if width>0:c.round((x,149,x+width,157),min(3,width/2),color)
            x+=width
    burn=cx.get('burn',{});hot=fresh(cx,180) and burn.get('alert',False)
    if hot:
        c.text(16,166,'Расход растёт',19,RED,True)
        leaders=burn.get('leaders',[])
        c.fit(16,190,session_label(leaders[0]) if leaders else 'См. виджет',208,2,17,18,color=RED)
    else:
        c.text(16,169,'Кэш',18,MUTED);c.text(224,169,compact(vals[0]) if valid else '—',21,PURPLE,'num','rt')
        c.text(16,199,'Выход',18,MUTED);c.text(224,199,compact(vals[2]) if valid else '—',21,CORAL,'num','rt')
    out['tokens']=c.finish()

    event,start=next_event(cal);delta=start-time.time() if start else None
    urgent=event and calendar_fresh(cal) and -300<=delta<=600
    c=Canvas('Встреча',RED if urgent else GOLD,3,'calendar')
    if event:
        dt=stamp(event['planned_date']);days=['ПН','ВТ','СР','ЧТ','ПТ','СБ','ВС'];months=['января','февраля','марта','апреля','мая','июня','июля','августа','сентября','октября','ноября','декабря']
        c.text(17,49,f'{days[dt.weekday()]}, {dt.day} {months[dt.month-1]}',18,MUTED)
        c.text(14,72,dt.strftime('%H:%M'),60,c.accent,'num')
        c.fit(17,137,event['subject'],205,2,23,26)
        if delta<=0:label='Встреча началась'
        elif delta>=86400:label=f'через {int(delta//86400)} д {int(delta%86400//3600)} ч'
        elif delta>=3600:label=f'через {int(delta//3600)} ч {int(delta%3600//60)} мин'
        else:label=f'через {max(1,int((delta+59)//60))} мин'
        c.round((12,196,228,223),8,'#352C1E' if not urgent else '#3D2030')
        c.fit(20,199,label if calendar_fresh(cal) else 'Данные устарели',204,1,18,color=c.accent)
    else:
        c.icon('calendar',90,65,60,GOLD)
        c.fit(25,147,'Пока нет встреч' if calendar_fresh(cal) else 'Нет связи с календарём',190,2,20)
    out['calendar']=c.finish()
    # Persistent usage/waiting alerts stay on their cards without starving rotation.
    return out, 'calendar' if urgent else None
