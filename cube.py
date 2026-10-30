"""Optional stock HelloCubic-Lite/SmallTV-Ultra display. No discovery or firmware changes."""
import io
import ipaddress
import hashlib
import json
from pathlib import Path
import time
from urllib.parse import quote
from urllib.request import Request, build_opener
import uuid
from calendars import NoRedirect


def host_url(host):
    host = host.strip()
    address = ipaddress.ip_address(host)
    if address.version != 4 or not (address.is_private or address.is_loopback) or address.is_unspecified or address.is_multicast:
        raise ValueError('Cube needs a private IPv4 address')
    return 'http://' + str(address)


class Cube:
    def __init__(self):
        self.host = None
        self.last = 0
        self.frame = 0
        self.uploaded = {}
        self.prepared = False
        self.opener = build_opener(NoRedirect)

    def request(self, path, data=None, headers=None):
        request = Request(self.host + path, data=data, headers=headers or {}, method='POST' if data is not None else 'GET')
        with self.opener.open(request, timeout=4) as response:
            return response.read(1024 * 1024)

    def update(self, config, snapshot, now=None):
        if not config['enabled']:
            self.host = None
            return {'enabled': False}
        now = time.time() if now is None else now
        host = host_url(config['host'])
        if host != self.host:
            self.host, self.last = host, 0
            self.uploaded, self.prepared = {}, False
            try:
                version = json.loads(self.request('/v.json'))
            except Exception:
                self.host = None
                raise
            if version.get('m') not in ('HelloCubic-Lite', 'SmallTV-Ultra'):
                self.host = None
                raise ValueError('Unsupported cube model')
        if now - self.last < 30:
            return {'enabled': True, 'checked_at': self.last}
        page = page_for(snapshot, self.frame)
        blink = page == 'calendar' and urgent_meeting(snapshot)
        content, extension = encode(render(snapshot, config, self.frame), blink)
        filename = 'aiti_rhythm_' + page + extension
        boundary = '----aiti' + uuid.uuid4().hex
        body = (f'--{boundary}\r\nContent-Disposition: form-data; name="file"; filename="{filename}"\r\n'
                'Content-Type: '+('image/gif' if blink else 'image/jpeg')+'\r\n\r\n').encode() + content + f'\r\n--{boundary}--\r\n'.encode()
        digest = hashlib.sha256(content).hexdigest()
        if self.uploaded.get(filename) != digest:
            self.request('/doUpload?dir=%2Fimage%2F', body, {'Content-Type': 'multipart/form-data; boundary=' + boundary})
            self.uploaded[filename] = digest
        if not self.prepared:
            self.request('/set?autoplay=0')
            self.request('/set?theme=2')
            self.prepared = True
        self.request('/set?img=' + quote('/image/' + filename, safe=''))
        self.last, self.frame = now, self.frame + 1
        return {'enabled': True, 'checked_at': now}


def page_for(snapshot, frame):
    if urgent_meeting(snapshot):
        return 'calendar'
    pages = ['limits', 'sessions', 'usage'] + (['calendar'] if snapshot.get('calendar', {}).get('enabled') else [])
    return pages[frame % len(pages)]


def urgent_meeting(snapshot):
    from datetime import datetime
    calendar = snapshot.get('calendar', {})
    if not calendar.get('enabled') or calendar.get('error') or time.time() - calendar.get('checked_at', 0) > 180:
        return False
    for row in calendar.get('events', []):
        if not row.get('all_day') and 0 < datetime.fromisoformat(row['planned_date']).timestamp() - time.time() <= 300:
            return True
    return False


def encode(image, blink=False):
    from PIL import Image, ImageDraw
    if not blink:
        result = io.BytesIO(); image.save(result, format='JPEG', quality=85)
        return result.getvalue(), '.jpg'
    frames = []
    for color in ('#79521D', '#FFD34D', '#79521D', '#FFD34D'):
        frame = image.copy(); ImageDraw.Draw(frame).rectangle((0, 0, 239, 239), outline=color, width=10)
        frames.append(frame.convert('P'))
    result = io.BytesIO()
    frames[0].save(result, format='GIF', save_all=True, append_images=frames[1:], duration=600, loop=0)
    return result.getvalue(), '.gif'


def render(snapshot, config, frame=0):
    from PIL import Image, ImageDraw, ImageFont
    image = Image.new('RGB', (240, 240), '#151B22')
    draw = ImageDraw.Draw(image)
    font_path = Path('C:/Windows/Fonts/segoeui.ttf')
    font = ImageFont.truetype(str(font_path), 17) if font_path.exists() else ImageFont.load_default()
    big = ImageFont.truetype(str(font_path), 27) if font_path.exists() else font
    calendar = snapshot.get('calendar', {})
    page = page_for(snapshot, frame)
    draw.text((12, 10), 'АйТи:Ритм', font=font, fill='#E5E8EB')
    if page == 'limits':
        quota = snapshot.get('limits', {})
        claude = snapshot.get('claude', {})
        codex_left = 100 * (1 - quota['weekly_pct']) if 'weekly_pct' in quota and not quota.get('error') and time.time() - quota.get('checked_at', 0) < 600 else None
        used = claude.get('limits', {}).get('seven_day', {}).get('used_percentage')
        claude_left = 100 - used if used is not None and not claude.get('error') and time.time() - (claude.get('limits_at') or 0) < 600 else None
        for y, provider, value in ((55, 'Codex', codex_left), (130, 'Claude', claude_left)):
            draw.text((12, y), provider + ' · остаток недели', font=font, fill='#939DA7')
            draw.text((12, y + 25), f'{max(0,min(100,value)):.1f}%' if value is not None else '—', font=big, fill='#E5E8EB')
    elif page == 'sessions':
        y = 52
        for provider in ('codex', 'claude'):
            data = snapshot.get(provider, {})
            active = [row for row in data.get('sessions', []) if row['status'] != 'idle']
            waiting = sum(row['status'] == 'waiting' for row in active)
            draw.text((12, y), provider.title(), font=font, fill='#939DA7')
            fresh = not data.get('error') and time.time() - data.get('checked_at', 0) < 180
            draw.text((12, y + 25), f'{len(active)} / ждут {waiting}' if fresh else 'Нет данных', font=big, fill='#76B6EF')
            y += 78
    elif page == 'usage':
        for y, provider in ((55, 'codex'), (130, 'claude')):
            tokens = snapshot.get(provider, {}).get('tokens', {})
            total = tokens.get('input', 0) + tokens.get('output', 0)
            draw.text((12, y), provider.title() + ' · токены за день', font=font, fill='#939DA7')
            data = snapshot.get(provider, {})
            fresh = not data.get('error') and time.time() - data.get('checked_at', 0) < 180
            draw.text((12, y + 25), f'{total:,}'.replace(',', ' ') if fresh else '—', font=big, fill='#E5E8EB')
    else:
        from datetime import datetime, timezone
        events = [row for row in calendar.get('events', []) if not row.get('all_day') and datetime.fromisoformat(row['planned_date']).timestamp() >= time.time() - 300]
        if urgent_meeting(snapshot):
            events = [row for row in events if 0 < datetime.fromisoformat(row['planned_date']).timestamp() - time.time() <= 300]
        event = events[0] if events else None
        fresh = not calendar.get('error') and time.time() - calendar.get('checked_at', 0) < 180
        draw.text((12, 55), 'Встречи' if fresh else 'Календарь устарел', font=font, fill='#939DA7')
        if event:
            start = datetime.fromisoformat(event['planned_date']).astimezone()
            draw.text((12, 90), start.strftime('%d.%m %H:%M'), font=big, fill='#E6B66B')
            delta = start.timestamp() - time.time()
            draw.text((12, 175), 'Через '+str(max(0,int((delta+59)//60)))+' мин' if delta > 0 else 'Встреча началась', font=font, fill='#E6B66B')
            if config.get('show_titles'):
                draw.text((12, 140), event['subject'][:22], font=font, fill='#E5E8EB')
        else:
            draw.text((12, 100), 'Нет ближайших', font=font, fill='#E5E8EB')
    image = image.rotate(int(config.get('rotation', 0)) % 360)
    return image
