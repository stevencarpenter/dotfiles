#!/usr/bin/env python3
"""Estimate AI coding-agent spend from local session logs (Claude Code + Codex).

Reads Claude Code logs (~/.claude/projects) and/or Codex rollout logs
(~/.codex/sessions), isolates a time window by per-message/per-turn timestamp,
and prices token usage with provider-correct cost models. Output is an API-rate
*equivalent*, not an invoice (a Max/Pro or ChatGPT subscription is a flat fee).

Stdlib only. See SKILL.md for usage.
"""
import argparse
import datetime as dt
import glob
import json
import os
import re
import sys
from collections import Counter, defaultdict

# --- Pricing (per MTok). Update the *_AS_OF stamps + tables when prices change,
#     or pass --rates rates.json to override without editing this file. ---------
RATES_AS_OF = "2026-06-02"

# Anthropic: cache writes are priced as multiples of base input; reads at 0.1x.
ANTH_CACHE = {"read": 0.10, "write_5m": 1.25, "write_1h": 2.0}
ANTHROPIC_RATES = {  # model-id prefix -> base input / output
    "claude-opus-4-8":   {"input": 5.0,  "output": 25.0, "fast_mult": 2.0},
    "claude-opus-4-7":   {"input": 5.0,  "output": 25.0},
    "claude-opus-4-6":   {"input": 5.0,  "output": 25.0},
    "claude-opus-4-5":   {"input": 5.0,  "output": 25.0},
    "claude-opus-4-1":   {"input": 15.0, "output": 75.0},
    "claude-opus-4":     {"input": 15.0, "output": 75.0},
    "claude-sonnet-4-6": {"input": 3.0,  "output": 15.0},
    "claude-sonnet-4-5": {"input": 3.0,  "output": 15.0},
    "claude-sonnet-4":   {"input": 3.0,  "output": 15.0},
    "claude-haiku-4-5":  {"input": 1.0,  "output": 5.0},
    "claude-haiku-3-5":  {"input": 0.8,  "output": 4.0},
}
# Anthropic per-call billing modifiers detected from the usage object.
ANTH_FAST_MULT = 6.0    # speed == "fast" (default; overridable per-model via fast_mult)
ANTH_BATCH_MULT = 0.5   # service_tier == "batch"
ANTH_US_GEO_MULT = 1.1  # inference_geo == "us"

# OpenAI/Codex: cached input is a discounted read (no cache-write cost, no TTL);
# reasoning tokens are already included in output_tokens. Optional "lc" applies
# when input_tokens exceeds the long-context threshold.
OPENAI_RATES = {  # model-id prefix -> input / cached / output (+ optional lc)
    "gpt-5.5":            {"input": 5.0,  "cached": 0.50,  "output": 30.0,
                            "lc": {"threshold": 272000, "input": 10.0, "cached": 1.0, "output": 45.0}},
    "gpt-5.4-mini":       {"input": 0.75, "cached": 0.075, "output": 4.5},
    "gpt-5.4":            {"input": 2.5,  "cached": 0.25,  "output": 15.0,
                            "lc": {"threshold": 272000, "input": 5.0, "cached": 0.5, "output": 22.5}},
    "gpt-5.3-codex":      {"input": 1.75, "cached": 0.175, "output": 14.0},
    # ESTIMATE (not on the public pricing page; codex-mini tier). Override via --rates.
    "gpt-5.1-codex-mini": {"input": 1.5,  "cached": 0.375, "output": 6.0},
}

CLAUDE_NAMES = {
    "claude-opus-4-8": "Opus 4.8", "claude-opus-4-7": "Opus 4.7",
    "claude-opus-4-6": "Opus 4.6", "claude-opus-4-5": "Opus 4.5",
    "claude-opus-4-1": "Opus 4.1",
    "claude-sonnet-4-6": "Sonnet 4.6", "claude-sonnet-4-5": "Sonnet 4.5",
    "claude-haiku-4-5": "Haiku 4.5", "claude-haiku-3-5": "Haiku 3.5",
}

_SID_RE = re.compile(r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}")


# --------------------------------------------------------------------------- #
# Rates / lookup
# --------------------------------------------------------------------------- #
def load_rates(path):
    anth = {k: dict(v) for k, v in ANTHROPIC_RATES.items()}
    oai = {k: dict(v) for k, v in OPENAI_RATES.items()}
    cache = dict(ANTH_CACHE)
    if path:
        with open(path) as fh:
            override = json.load(fh)
        if "_cache_multipliers" in override:
            cache.update(override.pop("_cache_multipliers"))
        # Per-field merge: update each model's fields without dropping unlisted ones.
        for model_id, fields in override.get("anthropic", {}).items():
            if model_id not in anth:
                anth[model_id] = {}
            anth[model_id].update(fields)
        for model_id, fields in override.get("openai", {}).items():
            if model_id not in oai:
                oai[model_id] = {}
            oai[model_id].update(fields)
    return {
        "anthropic": anth, "openai": oai, "cache": cache,
        "anth_keys": sorted(anth, key=len, reverse=True),
        "oai_keys": sorted(oai, key=len, reverse=True),
    }


def _lookup(model_id, table, keys):
    for k in keys:
        if model_id == k or model_id.startswith(k):
            return table[k]
    return None


# --------------------------------------------------------------------------- #
# Time window
# --------------------------------------------------------------------------- #
def parse_ts(ts):
    try:
        dt_obj = dt.datetime.fromisoformat(ts.replace("Z", "+00:00"))
        # If still naive (no trailing Z or offset), assume UTC.
        if dt_obj.tzinfo is None:
            dt_obj = dt_obj.replace(tzinfo=dt.timezone.utc)
        return dt_obj
    except Exception:
        return None


def local_tz():
    """Best-effort IANA local tz so bucketing is DST-correct across the year."""
    try:
        from zoneinfo import ZoneInfo
        link = os.readlink("/etc/localtime")
        if "zoneinfo/" in link:
            return ZoneInfo(link.split("zoneinfo/")[-1])
    except Exception:
        pass
    tzv = os.environ.get("TZ")
    if tzv:
        try:
            from zoneinfo import ZoneInfo
            return ZoneInfo(tzv)
        except Exception:
            pass
    # Fallback: use UTC rather than a fixed-offset tzinfo.
    return dt.timezone.utc


def period_bounds(gran, period, trailing, tz, now):
    if trailing:
        days = {"day": 1, "week": 7, "month": 30, "year": 365}[gran]
        return now - dt.timedelta(days=days), now, f"trailing {days}d ending {now:%Y-%m-%d %H:%M %Z}"

    def at(y, m, d):
        return dt.datetime(y, m, d, tzinfo=tz)

    if gran == "day":
        d = dt.date.fromisoformat(period) if period else now.date()
        start = at(d.year, d.month, d.day)
        return start, start + dt.timedelta(days=1), d.isoformat()
    if gran == "week":
        if period:
            try:
                y, w = period.upper().split("-W")
                monday = dt.date.fromisocalendar(int(y), int(w), 1)
            except (ValueError, IndexError) as e:
                raise ValueError(f"Invalid week format (expected YYYY-Www): {period}") from e
        else:
            monday = now.date() - dt.timedelta(days=now.weekday())
        start = at(monday.year, monday.month, monday.day)
        iso = monday.isocalendar()
        return start, start + dt.timedelta(days=7), f"{iso[0]}-W{iso[1]:02d} (wk of {monday.isoformat()})"
    if gran == "month":
        if period:
            try:
                y, m = (int(x) for x in period.split("-"))
            except (ValueError, IndexError) as e:
                raise ValueError(f"Invalid month format (expected YYYY-MM): {period}") from e
        else:
            y, m = now.year, now.month
        start = at(y, m, 1)
        end = at(y + 1, 1, 1) if m == 12 else at(y, m + 1, 1)
        return start, end, f"{y}-{m:02d}"
    try:
        y = int(period) if period else now.year
    except ValueError as e:
        raise ValueError(f"Invalid year format (expected YYYY): {period}") from e
    return at(y, 1, 1), at(y + 1, 1, 1), str(y)


def bucket_key(when, gran, by_day):
    if by_day or gran in ("day", "week", "month"):
        return when.date().isoformat()
    return when.strftime("%Y-%m")


# --------------------------------------------------------------------------- #
# Claude Code scan + pricing
# --------------------------------------------------------------------------- #
def scan_claude(logdir, start, end, tz, gran, by_day):
    files = glob.glob(os.path.join(os.path.expanduser(logdir), "**", "*.jsonl"), recursive=True)
    seen = {}
    raw = 0
    for fp in files:
        try:
            fh = open(fp, "r", errors="replace")
        except OSError:
            continue
        with fh:
            for line in fh:
                if '"usage"' not in line:
                    continue
                try:
                    d = json.loads(line)
                except Exception:
                    continue
                if d.get("type") != "assistant":
                    continue
                msg = d.get("message") or {}
                u = msg.get("usage")
                if not isinstance(u, dict) or msg.get("model") == "<synthetic>":
                    continue
                when = parse_ts(d.get("timestamp", ""))
                if when is None or not (start <= when < end):
                    continue
                raw += 1
                cc = u.get("cache_creation") or {}
                fields = {
                    "inp": u.get("input_tokens", 0) or 0,
                    "out": u.get("output_tokens", 0) or 0,
                    "cr": u.get("cache_read_input_tokens", 0) or 0,
                    "cc": u.get("cache_creation_input_tokens", 0) or 0,
                    "c5": cc.get("ephemeral_5m_input_tokens", 0) or 0,
                    "c1": cc.get("ephemeral_1h_input_tokens", 0) or 0,
                }
                mid = msg.get("id") or d.get("requestId") or d.get("uuid") or f"_nokey_{fp}_{raw}"
                rec = seen.get(mid)
                if rec is None:
                    seen[mid] = {
                        "provider": "claude", "model": msg.get("model", "?"),
                        "day": bucket_key(when.astimezone(tz), gran, by_day),
                        "fast": u.get("speed") == "fast",
                        "batch": u.get("service_tier") == "batch",
                        "us": u.get("inference_geo") == "us",
                        "t": fields,
                    }
                else:
                    # Max-merge per field, but cap total at reported cc to avoid overcounting cache.
                    for k, v in fields.items():
                        if v > rec["t"][k]:
                            rec["t"][k] = v
                    # Rebalance if c5+c1 now exceeds cc (possible after per-field max-merge).
                    if rec["t"]["c5"] + rec["t"]["c1"] > rec["t"]["cc"]:
                        excess = rec["t"]["c5"] + rec["t"]["c1"] - rec["t"]["cc"]
                        rec["t"]["c5"] = max(0, rec["t"]["c5"] - excess)
    return list(seen.values()), raw, len(files)


def price_claude(rec, rates):
    rate = _lookup(rec["model"], rates["anthropic"], rates["anth_keys"])
    if rate is None:
        return None, None
    bi, bo = rate["input"], rate["output"]
    fast_mult = rate.get("fast_mult", ANTH_FAST_MULT)
    cm = rates["cache"]
    t = rec["t"]
    c5, c1 = t["c5"], t["c1"]
    rem = t["cc"] - c5 - c1
    if rem > 0:
        c5 += rem
    # Safety: if c5+c1 > cc (possible after per-field max-merge), reset to cc.
    if c5 + c1 > t["cc"]:
        c5 = max(0, t["cc"] - c1)
    buckets = [
        ("input (uncached)", t["inp"], bi),
        ("cache read", t["cr"], bi * cm["read"]),
        ("cache write 5m", c5, bi * cm["write_5m"]),
        ("cache write 1h", c1, bi * cm["write_1h"]),
        ("output", t["out"], bo),
    ]
    nominal = [(label, tok, r, tok * r / 1e6) for label, tok, r in buckets]
    fbi, fbo = (bi * fast_mult, bo * fast_mult) if rec["fast"] else (bi, bo)
    actual = (t["inp"] * fbi + t["out"] * fbo + t["cr"] * fbi * cm["read"]
              + c5 * fbi * cm["write_5m"] + c1 * fbi * cm["write_1h"]) / 1e6
    if rec["batch"]:
        actual *= ANTH_BATCH_MULT
    if rec["us"]:
        actual *= ANTH_US_GEO_MULT
    flags = [f for f, on in (("fast", rec["fast"]), ("batch", rec["batch"]), ("us-geo", rec["us"])) if on]
    return nominal, (actual, flags, fast_mult)


def claude_display(model, rates):
    for k in rates["anth_keys"]:
        if model == k or model.startswith(k):
            return CLAUDE_NAMES.get(k, model)
    return model


# --------------------------------------------------------------------------- #
# Codex scan + pricing
# --------------------------------------------------------------------------- #
def scan_codex(codex_base, start, end, tz, gran, by_day):
    base = os.path.expanduser(codex_base)
    files = glob.glob(os.path.join(base, "sessions", "**", "*.jsonl"), recursive=True)
    files += glob.glob(os.path.join(base, "archived_sessions", "**", "*.jsonl"), recursive=True)
    by_sid = {}
    for fp in files:
        m = _SID_RE.search(os.path.basename(fp))
        by_sid.setdefault(m.group(0) if m else fp, fp)

    records = []
    events = 0
    for fp in by_sid.values():
        cur_model = None
        try:
            fh = open(fp, "r", errors="replace")
        except OSError:
            continue
        with fh:
            for line in fh:
                if '"token_count"' not in line and '"turn_context"' not in line and '"session_meta"' not in line:
                    continue
                try:
                    d = json.loads(line)
                except Exception:
                    continue
                p = d.get("payload") or {}
                kind = d.get("type")
                if kind == "turn_context" and p.get("model"):
                    cur_model = p["model"]
                elif kind == "session_meta" and not cur_model and p.get("model"):
                    cur_model = p["model"]
                elif kind == "event_msg" and p.get("type") == "token_count":
                    when = parse_ts(d.get("timestamp", ""))
                    if when is None or not (start <= when < end):
                        continue
                    info = p.get("info") or {}
                    last = info.get("last_token_usage") or {}
                    inp = last.get("input_tokens", 0) or 0
                    cached = last.get("cached_input_tokens", 0) or 0
                    out = last.get("output_tokens", 0) or 0
                    if inp == 0 and out == 0:
                        continue
                    events += 1
                    records.append({
                        "provider": "codex", "model": cur_model or "?",
                        "day": bucket_key(when.astimezone(tz), gran, by_day),
                        "t": {"input": inp, "cached": cached, "output": out},
                    })
    return records, events, len(by_sid)


def price_codex(rec, rates):
    rate = _lookup(rec["model"], rates["openai"], rates["oai_keys"])
    if rate is None:
        return None, None
    t = rec["t"]
    inp_total = t["input"]            # cached-inclusive
    cached = min(t["cached"], inp_total)
    uncached = inp_total - cached
    out = t["output"]
    std_buckets = [
        ("input (uncached)", uncached, rate["input"]),
        ("cached input", cached, rate["cached"]),
        ("output", out, rate["output"]),
    ]
    nominal = [(label, tok, r, tok * r / 1e6) for label, tok, r in std_buckets]
    lc = rate.get("lc")
    use_lc = bool(lc and inp_total > lc["threshold"])
    eff = lc if use_lc else rate
    actual = (uncached * eff["input"] + cached * eff["cached"] + out * eff["output"]) / 1e6
    return nominal, (actual, (["long-ctx"] if use_lc else []), None)


# --------------------------------------------------------------------------- #
# Aggregation + reporting
# --------------------------------------------------------------------------- #
def fmt_int(n):
    return f"{n:,}"


def usd(x):
    return f"${x:,.2f}"


def aggregate(records, rates):
    pricer = {"claude": price_claude, "codex": price_codex}
    namer = {"claude": lambda m: claude_display(m, rates), "codex": lambda m: m}
    agg = {}            # (provider, display) -> dict
    by_day = defaultdict(float)
    unknown = defaultdict(Counter)   # provider -> Counter(model)
    for rec in records:
        nominal, extra = pricer[rec["provider"]](rec, rates)
        if nominal is None:
            unknown[rec["provider"]][rec["model"]] += 1
            continue
        actual, flags, fast_mult = extra
        key = (rec["provider"], namer[rec["provider"]](rec["model"]))
        a = agg.get(key)
        if a is None:
            a = agg[key] = {"calls": 0, "order": [lbl for lbl, *_ in nominal],
                            "tok": Counter(), "rate": {}, "nominal": Counter(),
                            "actual": 0.0, "flags": Counter()}
        if rec["provider"] == "claude":
            a["fast_mult"] = fast_mult
        a["calls"] += 1
        for label, tok, r, cost in nominal:
            a["tok"][label] += tok
            a["rate"][label] = r
            a["nominal"][label] += cost
        a["actual"] += actual
        for f in flags:
            a["flags"][f] += 1
        by_day[rec["day"]] += actual
    return agg, by_day, unknown


PROVIDER_TITLE = {"claude": "CLAUDE CODE (Anthropic)", "codex": "CODEX (OpenAI)"}


def print_provider(provider, agg, unknown, width):
    models = sorted([(k, v) for k, v in agg.items() if k[0] == provider],
                    key=lambda kv: -kv[1]["actual"])
    if not models and not unknown.get(provider):
        return 0.0
    print("\n" + "-" * width)
    print(PROVIDER_TITLE[provider])
    if unknown.get(provider):
        print(f"  !! UNPRICED models (add to rate table): {dict(unknown[provider])}")
    subtotal = 0.0
    comp = Counter()
    for (_, name), a in models:
        subtotal += a["actual"]
        print(f"\n  {name}  ({fmt_int(a['calls'])} calls)")
        print(f"    {'bucket':<18}{'tokens':>16}{'$/MTok':>10}{'cost':>14}")
        for label in a["order"]:
            r = a["rate"][label]
            print(f"    {label:<18}{fmt_int(a['tok'][label]):>16}{r:>10.2f}{usd(a['nominal'][label]):>14}")
            comp[label] += a["nominal"][label]
        nominal_sum = sum(a["nominal"].values())
        if abs(a["actual"] - nominal_sum) > 0.005:
            mults = {"fast": a.get("fast_mult", ANTH_FAST_MULT), "batch": ANTH_BATCH_MULT, "us-geo": ANTH_US_GEO_MULT}
            parts = [f"{mults[f]:.1f}x" if f in mults else f for f in a["flags"].keys()]
            note = "adj" + (f" ({', '.join(parts)})" if parts else "")
            print(f"    {note:<28}{usd(a['actual'] - nominal_sum):>30}")
        print(f"    {'SUBTOTAL':<18}{'':>16}{'':>10}{usd(a['actual']):>14}")
    print(f"\n  {PROVIDER_TITLE[provider]} subtotal: {usd(subtotal)}")
    csum = sum(comp.values()) or 1.0
    parts = "  ".join(f"{lbl} {100*v/csum:.0f}%" for lbl, v in comp.most_common())
    print(f"  composition: {parts}")
    return subtotal


def main():
    ap = argparse.ArgumentParser(description="Estimate Claude Code + Codex API-rate spend from local logs.")
    ap.add_argument("granularity", nargs="?", default="month", choices=["day", "week", "month", "year"])
    ap.add_argument("period", nargs="?", default=None,
                    help="explicit target: day=YYYY-MM-DD, week=YYYY-Www, month=YYYY-MM, year=YYYY")
    ap.add_argument("--provider", default="all", choices=["claude", "codex", "all"],
                    help="which agent's logs to price (default: all)")
    ap.add_argument("--trailing", action="store_true", help="rolling window (1d/7d/30d/365d)")
    ap.add_argument("--dir", default="~/.claude/projects", help="Claude logs directory")
    ap.add_argument("--codex-dir", default="~/.codex", help="Codex base directory")
    ap.add_argument("--rates", default=None, help="JSON file overriding the built-in rate tables")
    ap.add_argument("--json", action="store_true", help="emit JSON instead of a table")
    ap.add_argument("--utc", action="store_true", help="bucket by UTC (default: system local tz)")
    ap.add_argument("--by-day", action="store_true", help="force a per-day breakdown")
    args = ap.parse_args()

    tz = dt.timezone.utc if args.utc else local_tz()
    now = dt.datetime.now(tz)
    if args.trailing and args.period:
        print("note: --trailing ignores the explicit PERIOD argument", file=sys.stderr)
    start, end, label = period_bounds(args.granularity, args.period, args.trailing, tz, now)
    rates = load_rates(args.rates)

    providers = ["claude", "codex"] if args.provider == "all" else [args.provider]
    records, scan_info = [], {}
    if "claude" in providers:
        recs, raw, nfiles = scan_claude(args.dir, start, end, tz, args.granularity, args.by_day)
        records += recs
        scan_info["claude"] = {"unique": len(recs), "raw": raw, "files": nfiles}
    if "codex" in providers:
        recs, evts, nsess = scan_codex(args.codex_dir, start, end, tz, args.granularity, args.by_day)
        records += recs
        scan_info["codex"] = {"turns": evts, "sessions": nsess}

    agg, by_day, unknown = aggregate(records, rates)
    tzname = "UTC" if args.utc else "local"

    if args.json:
        out = {
            "tool": "ai-cost", "rates_as_of": RATES_AS_OF, "providers": providers,
            "granularity": args.granularity, "trailing": args.trailing,
            "period_label": label, "timezone": tzname,
            "window_start": start.isoformat(), "window_end": end.isoformat(),
            "scan": scan_info,
            "total_usd": round(sum(a["actual"] for a in agg.values()), 4),
            "by_provider": {
                prov: round(sum(a["actual"] for k, a in agg.items() if k[0] == prov), 4)
                for prov in providers},
            "by_model": {
                f"{k[0]}:{k[1]}": {
                    "calls": a["calls"],
                    "tokens": dict(a["tok"]),
                    "cost_usd": round(a["actual"], 4),
                } for k, a in agg.items()},
            "cost_by_bucket": {k: round(v, 4) for k, v in sorted(by_day.items())},
            "unknown_models": {p: dict(c) for p, c in unknown.items()},
        }
        print(json.dumps(out, indent=2))
        return

    W = 78
    print("=" * W)
    kind = "trailing" if args.trailing else args.granularity
    print(f"AI CODING SPEND (API-rate equiv)  —  {kind}: {label}  ({tzname} tz)")
    print("=" * W)
    print(f"Window:  {start:%Y-%m-%d %H:%M} → {end:%Y-%m-%d %H:%M}")
    if "claude" in scan_info:
        s = scan_info["claude"]
        print(f"Claude:  {fmt_int(s['files'])} files, {fmt_int(s['raw'])} lines → "
              f"{fmt_int(s['unique'])} unique calls")
    if "codex" in scan_info:
        s = scan_info["codex"]
        print(f"Codex:   {fmt_int(s['sessions'])} sessions → {fmt_int(s['turns'])} billed turns")

    if not agg:
        print("\nNo usage found in this window.")
        return

    grand = 0.0
    for prov in providers:
        grand += print_provider(prov, agg, unknown, W)

    print("\n" + "=" * W)
    if len(providers) > 1:
        for prov in providers:
            sub = sum(a["actual"] for k, a in agg.items() if k[0] == prov)
            print(f"  {PROVIDER_TITLE[prov]:<32}{usd(sub):>42}")
    print(f"{'GRAND TOTAL':<40}{usd(grand):>38}")
    print("=" * W)

    if by_day and not (args.granularity == "day" and not args.by_day):
        peak = max(by_day.values())
        unit = "day" if (args.by_day or args.granularity in ("day", "week", "month")) else "month"
        print(f"\nTotal spend by {unit}:")
        for k in sorted(by_day):
            bar = "#" * int(by_day[k] / peak * 40) if peak else ""
            print(f"  {k}  {usd(by_day[k]):>11}  {bar}")

    print(f"\nRates as of {RATES_AS_OF}. API-rate equivalent, NOT an invoice "
          f"(subscriptions are flat fees).")


if __name__ == "__main__":
    main()
