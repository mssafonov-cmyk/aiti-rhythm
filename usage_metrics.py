"""Shared presentation metadata. Missing time series are never reconstructed from totals."""
import json
import math
import re
from burn import classify, day_start_msk
from safeio import atomic_json

PROVIDERS = (('codex', 'Codex', 'C', '#56D8F1'), ('claude', 'Claude', 'Cl', '#BAABFF'),
             ('antigravity', 'Antigravity', 'AG', '#99DDAA'))


def known_source(source, now):
    at = source.get('checked_at')
    start = day_start_msk(now)
    return (type(at) in (int, float) and start <= at <= now and now-at < 180
            and source.get('usage_day', start) == start and not source.get('error')
            and source.get('status') not in ('journals_not_found', 'not_installed'))


def day_total(source, key, now):
    if not known_source(source, now) or (key == 'antigravity' and not source.get('observed')):
        return None
    tokens = source.get('tokens')
    if not isinstance(tokens, dict):
        return None
    values = [tokens.get(k, 0) for k in ('input', 'output')]
    if not all(type(x) in (int, float) and math.isfinite(x) and x >= 0 and x == int(x) for x in values):
        return None
    return int(sum(values))


class DailyUsageMemory:
    """Only daily scalar totals, source fingerprints and timestamps; never messages/auth."""
    def __init__(self, root):
        self.path = root / 'daily-token-totals.json'
        self.day, self.entries, self.dirty, self.next_save = None, {}, False, 0
        try:
            raw = json.loads(self.path.read_text(encoding='utf-8-sig'))
            if raw.get('version') == 1 and type(raw.get('day')) is int and isinstance(raw.get('sources'), dict):
                self.day = raw['day']
                for key, value in raw['sources'].items():
                    if (key in {p[0] for p in PROVIDERS} and isinstance(value, dict)
                            and isinstance(value.get('identity'), str) and re.fullmatch('[a-f0-9]{64}', value['identity'])
                            and type(value.get('total')) is int and value['total'] >= 0
                            and type(value.get('at')) in (int, float) and math.isfinite(value['at'])
                            and self.day <= value['at'] < self.day+86400):
                        self.entries[key] = dict(identity=value['identity'], total=value['total'], at=value['at'], partial=value.get('partial') is True)
        except (OSError, ValueError, TypeError, AttributeError):
            pass

    def enrich(self, snapshot, identities, now):
        start = day_start_msk(now)
        if self.day != start:
            self.day, self.entries, self.dirty = start, {}, True
        result = dict(snapshot)
        for key, _, _, _ in PROVIDERS:
            identity = identities.get(key)
            old = self.entries.get(key)
            if old and old['identity'] != identity:
                del self.entries[key]; old = None; self.dirty = True
            source = snapshot.get(key, {})
            if source.get('enabled') is False or not identity:
                continue
            total = day_total(source, key, now)
            if total is not None and (old is None or total >= old['total']):
                new = dict(identity=identity, total=total, at=source['checked_at'], partial=bool(source.get('usage_partial')))
                if new != old:
                    self.entries[key] = new; self.dirty = True
                old = new
            if old and (total is None or total < old['total']):
                result[key] = dict(source, day_memory=dict(total=old['total'], at=old['at'], partial=old.get('partial', False)))
                if key == 'antigravity' and 'available' not in source:
                    result[key]['available'] = True
        if self.dirty and now >= self.next_save:
            try:
                atomic_json(self.path, dict(version=1, day=self.day, sources=self.entries))
                self.dirty = False
            except OSError:
                self.next_save = now+10  # Retain RAM values even if the optional checkpoint cannot be written.
        return result


def combined_usage(snapshot, now):
    providers, leaders, bars, rates, baselines = [], [], {}, [], []
    hot, window = False, 900
    for key, name, short, color in PROVIDERS:
        source = snapshot.get(key, {})
        if source.get('enabled') is False or (key == 'antigravity' and not source.get('available')):
            continue
        held = source.get('day_memory') or {}
        known = (known_source(source, now) and not held
                 and (key != 'antigravity' or source.get('observed')))
        tokens, burn = source.get('tokens'), source.get('burn') or {}
        rate = burn.get('per_min') if known and source.get('observed') else None
        series = burn.get('series', []) if known and source.get('observed') else []
        providers.append(dict(key=key, name=name, short=short, color=color, series=series,
                              partial=bool(held.get('partial', source.get('usage_partial'))),
                              cached_day=bool(held), day_updated_at=held.get('at', source.get('checked_at')),
                              day_tokens=held.get('total') if held else day_total(source, key, now),
                              per_min=rate, note=source.get('usage_note', 'Объём токенов с учётом кэша; не денежная стоимость.')))
        if rate is not None:
            window = burn.get('window_seconds', window)
            rates.append(rate)
            baselines.append(burn.get('baseline_per_min'))
            hot = hot or bool(burn.get('alert'))
            leaders.extend(dict(item, provider=name) for item in burn.get('leaders', []))
        for bar in series:
            bars[bar['at']] = bars.get(bar['at'], 0) + bar['tokens']
    rate = sum(rates)
    baseline = sum(baselines) if baselines and all(x is not None for x in baselines) else None
    leaders.sort(key=lambda x: (x.get('per_min', 0) if rate else x.get('day_tokens', 0)), reverse=True)
    incomplete = any(p['partial'] or p['cached_day'] or (p['per_min'] is None and (p['day_tokens'] or 0) > 0) for p in providers)
    return dict(providers=providers, observed=bool(rates), checked_at=now, partial=incomplete,
                burn=dict(per_min=rate, baseline_per_min=baseline, window_seconds=window,
                          ratio=round(rate / baseline, 1) if baseline else None,
                          level=classify(rate, baseline), alert=hot, leaders=leaders[:10],
                          leader_basis='window' if rate else 'day',
                          series=[dict(at=at, tokens=value, per_min=round(value / 15)) for at, value in sorted(bars.items())]))
