"""Shared presentation metadata. Missing time series are never reconstructed from totals."""
from burn import classify

PROVIDERS = (('codex', 'Codex', 'C', '#56D8F1'), ('claude', 'Claude', 'Cl', '#BAABFF'),
             ('antigravity', 'Antigravity', 'AG', '#99DDAA'))


def combined_usage(snapshot, now):
    providers, leaders, bars, rates, baselines = [], [], {}, [], []
    hot, window = False, 900
    for key, name, short, color in PROVIDERS:
        source = snapshot.get(key, {})
        if source.get('enabled') is False or (key == 'antigravity' and not source.get('available')):
            continue
        fresh = bool(source.get('checked_at') and 0 <= now - source['checked_at'] < 180 and not source.get('error'))
        known = (fresh and source.get('status') not in ('journals_not_found', 'not_installed')
                 and (key != 'antigravity' or source.get('observed')))
        tokens, burn = source.get('tokens'), source.get('burn') or {}
        rate = burn.get('per_min') if known and source.get('observed') else None
        series = burn.get('series', []) if known and source.get('observed') else []
        providers.append(dict(key=key, name=name, short=short, color=color, series=series,
                              partial=bool(source.get('usage_partial')),
                              day_tokens=tokens.get('input', 0) + tokens.get('output', 0) if known and tokens else None,
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
    return dict(providers=providers, observed=bool(rates), checked_at=now, partial=any(p['partial'] for p in providers),
                burn=dict(per_min=rate, baseline_per_min=baseline, window_seconds=window,
                          ratio=round(rate / baseline, 1) if baseline else None,
                          level=classify(rate, baseline), alert=hot, leaders=leaders[:10],
                          leader_basis='window' if rate else 'day',
                          series=[dict(at=at, tokens=value, per_min=round(value / 15)) for at, value in sorted(bars.items())]))
