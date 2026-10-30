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
            space = json.loads(self.request('/space.json'))
            if space.get('free', 0) < len(content) + 20000:
                raise RuntimeError('Not enough cube space; existing images preserved')
            self.request('/doUpload?dir=%2Fimage%2F', body, {'Content-Type': 'multipart/form-data; boundary=' + boundary})
            received = self.request('/image/' + filename)
            if received != content:
                raise RuntimeError('Cube image upload verification failed')
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
        result = io.BytesIO(); image.save(result, format='JPEG', quality=88, optimize=True)
        return result.getvalue(), '.jpg'
    frames = []
    for strength in (0, 80, 170, 255, 170, 80):
        frame = image.convert('RGB').copy()
        overlay = frame.copy()
        ImageDraw.Draw(overlay).rectangle((0, 0, 239, 239), outline='#FFD43B', width=16)
        frames.append(Image.blend(frame, overlay, strength / 255))
    palette = frames[3].quantize(colors=128)
    frames = [frame.quantize(palette=palette, dither=Image.Dither.NONE) for frame in frames]
    result = io.BytesIO()
    frames[0].save(result, format='GIF', save_all=True, append_images=frames[1:],
                   duration=[600, 200, 200, 600, 200, 200], loop=0, optimize=True, disposal=1)
    return result.getvalue(), '.gif'


def render(snapshot, config, frame=0):
    from copy import deepcopy
    from cube_art import render_cards, fresh, age, next_event, calendar_fresh, stamp
    # Restore the established prism artwork without importing private collectors.
    data = deepcopy(snapshot)
    for event in data.get('calendar', {}).get('events', []):
        # Keep the current app's local-time display for calendars that send UTC.
        event['planned_date'] = stamp(event['planned_date']).astimezone().isoformat()
        if not config.get('show_titles'):
            event['subject'] = 'Название скрыто'
    cards, _ = render_cards(data, fresh, age, next_event, calendar_fresh)
    key = {'sessions': 'agents', 'usage': 'tokens'}.get(page_for(data, frame), page_for(data, frame))
    return cards[key].rotate(int(config.get('rotation', 0)) % 360)
