"""Persistent daily high-water marks, isolated by the actual source identity."""
from datetime import date
import json
import math
import re
from safeio import atomic_json
from history_readers import day
from usage_metrics import day_total

PROVIDERS = ('codex', 'claude', 'antigravity')


def valid_time(value):
    return type(value) in (int, float) and math.isfinite(value) and 0 < value < 32503680000


def valid_row(row, today):
    try:
        return (isinstance(row, dict) and date.fromisoformat(row['date']).isoformat() == row['date']
                and '2020-01-01' <= row['date'] <= today
                and type(row['total']) is int and 0 <= row['total'] <= 10**16)
    except (ValueError, TypeError, KeyError):
        return False


class UsageHistory:
    def __init__(self, root):
        self.path = root / 'usage-history.json'
        self.sources, self.dirty, self.next_save = {}, False, 0
        self.save_error = False
        try:
            raw = json.loads(self.path.read_text(encoding='utf-8-sig'))
            if raw.get('version') == 1 and isinstance(raw.get('sources'), dict):
                for identity, entry in raw['sources'].items():
                    if (re.fullmatch('[a-f0-9]{64}', identity) and isinstance(entry, dict)
                            and entry.get('provider') in PROVIDERS and isinstance(entry.get('days'), dict)):
                        self.sources[identity] = dict(provider=entry['provider'], days={
                            d: dict(date=d, total=r['total'], partial=bool(r.get('partial')),
                                    at=r['at'], origin='journal' if r.get('origin') == 'journal' else 'monitor')
                            for d, r in entry['days'].items()
                            if valid_row(r, '9999-12-31') and d == r['date'] and valid_time(r.get('at'))})
        except (OSError, ValueError, TypeError, AttributeError):
            pass

    def merge(self, entry, row, at, origin):
        old = entry['days'].get(row['date'])
        value = dict(date=row['date'], total=row['total'], partial=bool(row.get('partial')),
                     at=at, origin=origin)
        if old and old['total'] > value['total']:
            return  # Repeated scans, deleted journals and transient errors cannot erase spend.
        if old and old['total'] == value['total']:
            value['partial'] = old.get('partial', True) and value['partial']
            if old.get('origin') == 'journal':
                value['origin'] = 'journal'
        if value != old:
            entry['days'][row['date']] = value
            self.dirty = True

    def enrich(self, snapshot, identities, imports, now):
        today, result = day(now), {}
        for provider in PROVIDERS:
            source, identity = snapshot.get(provider, {}), identities.get(provider)
            if source.get('enabled') is False or not identity:
                continue
            entry = self.sources.setdefault(identity, dict(provider=provider, days={}))
            imported = imports.get(provider) or {}
            imported_at = imported.get('checked_at', now)
            if not imported.get('error') and valid_time(imported_at) and imported_at <= now:
                for row in imported.get('days', []):
                    if valid_row(row, today):
                        self.merge(entry, row, imported_at, 'journal')
            total = day_total(source, provider, now)
            if total is not None:
                # Monitoring is a lower bound: the program may be closed before the day ends.
                self.merge(entry, dict(date=today, total=total, partial=True), source['checked_at'], 'monitor')
            rows = [r for d, r in sorted(entry['days'].items()) if d <= today]
            result[provider] = dict(days=rows, today=today, loading=not imported,
                                    error=bool(imported.get('error')), save_error=self.save_error)
        if self.dirty and now >= self.next_save:
            try:
                atomic_json(self.path, dict(version=1, sources=self.sources))
                self.dirty, self.save_error = False, False
                self.next_save = now + 15
            except OSError:
                self.save_error = True
                self.next_save = now + 15
        for value in result.values():
            value['save_error'] = self.save_error
        return result
