#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
OpenTokenUsage 本機快取真實帳號同步腳本 (Desktop SSOT Sync) - 支援多配額池 (Multi-Token Pools)
讀取 %APPDATA%/com.poweruserz.opentokenusage/usage-api-cache.json
並將 5 大專屬平台 (Cursor, Codex, Antigravity, Claude Code, Grok) 的最新真實數據
同步至 D1 資料庫或線上 Edge Worker API。
"""

import os
import re
import sys
import json
import math
import urllib.request
import urllib.error

CACHE_PATH = os.path.expandvars(r"%APPDATA%\com.poweruserz.opentokenusage\usage-api-cache.json")
REMOTE_API_URL = os.environ.get("SYNC_API_URL", "https://opentokenusage-web.chihfu-chen-tw.workers.dev/api/quotas/sync")

# 所有數值只取自快取快照的 lines；缺少的數字或日期一律不補，整筆缺就不上傳該平台。

# Google Antigravity 快照 lines 的標籤 (桌面端 OpenUsage AntigravityMetric) 與配額池對照。
# 每個池只放快照裡真的有的週期；週期順序決定平手時由誰主導 (每週優先)。
ANTIGRAVITY_POOLS = (
    ("gemini_models", "Gemini Models", (
        {"line": "Weekly", "id": "weekly", "label": "Weekly limit", "window": "每週", "metric": "Gemini (週)"},
        {"line": "Session", "id": "5h", "label": "5h limit", "window": "5小時", "metric": "Gemini (5h)"},
    )),
    ("claude_gpt", "Claude and GPT models", (
        {"line": "Claude Weekly", "id": "weekly", "label": "Weekly limit", "window": "每週", "metric": "Claude (週)"},
        {"line": "Claude", "id": "5h", "label": "5h limit", "window": "5小時", "metric": "Claude (5h)"},
    )),
    ("gemini_4_argon", "Gemini 4 Argon", (
        {"line": "Argon Weekly", "id": "weekly", "label": "Weekly limit", "window": "每週", "metric": "Argon"},
    )),
)
# 次要實驗模型池：不參與平台主數值，避免 Argon 耗盡把整個平台顯示成 0%
ANTIGRAVITY_SIDE_POOLS = {"gemini_4_argon"}

def load_local_cache():
    if not os.path.exists(CACHE_PATH):
        print(f"[警告] 找不到本機快取檔案: {CACHE_PATH}，將使用基準結構")
        return None
    with open(CACHE_PATH, "r", encoding="utf-8") as f:
        return json.load(f)

def _skip(provider, reason):
    print(f"[略過] {provider}: {reason}，本次不上傳此平台", file=sys.stderr)

def _number(value):
    """A finite JSON number, or None. Booleans and text are not usage figures."""
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    value = float(value)
    return value if math.isfinite(value) else None

def _percent_used(line):
    """Used share of a progress line in percent, or None when the line lacks a usable used/limit pair."""
    if not isinstance(line, dict):
        return None
    used = _number(line.get("used"))
    limit = _number(line.get("limit"))
    if used is None or limit is None or limit <= 0:
        return None
    return round(used / limit * 100.0, 2)

def _remaining(used_pct):
    return round(max(0.0, 100.0 - used_pct), 2)

def _label(line):
    value = line.get("label")
    return value if isinstance(value, str) else ""

def _reset_time(line):
    value = line.get("resetsAt")
    return value if isinstance(value, str) and value else None

def _kind(line):
    fmt = line.get("format")
    kind = fmt.get("kind") if isinstance(fmt, dict) else None
    return kind or "percent"

def _governing_window(session, weekly):
    """Tightest of the 5h and weekly windows, as (used %, resetsAt). On a tie the weekly window governs."""
    windows = [w for w in (weekly, session) if w is not None]
    return max(windows, key=lambda w: w[0]) if windows else None

def _antigravity_pool(pool_id, name, tiers):
    governing = min(tiers, key=lambda t: t["remaining"])
    for t in tiers:
        t["isGoverning"] = t is governing
    return {
        "id": pool_id,
        "name": name,
        "effectiveRemaining": governing["remaining"],
        "effectiveUsed": max(t["used"] for t in tiers),
        "primaryResetTime": governing["resetsAt"],
        "isCritical": governing["remaining"] <= 5.0,
        "tiers": tiers
    }

def _antigravity_record(c):
    # 每個標籤取第一條有可用數值的 progress line
    usable = {}
    for l in c.get("lines") or []:
        pct = _percent_used(l)
        lbl = l.get("label") if isinstance(l, dict) else None
        if pct is None or not isinstance(lbl, str) or not lbl or lbl in usable:
            continue
        usable[lbl] = (l, pct)

    pools = []
    metric_names = {}
    for pool_id, pool_name, specs in ANTIGRAVITY_POOLS:
        tiers = []
        for spec in specs:
            metric_names[spec["line"]] = spec["metric"]
            if spec["line"] not in usable:
                continue
            l, pct = usable[spec["line"]]
            tiers.append({
                "id": spec["id"],
                "label": spec["label"],
                "used": pct,
                "limit": 100.0,
                "remaining": _remaining(pct),
                "resetsAt": _reset_time(l),
                "resetDurationText": spec["window"]
            })
        if tiers:
            pools.append(_antigravity_pool(pool_id, pool_name, tiers))

    # 對照表以外的新標籤：各自成池，名稱沿用原標籤 (動態成池)
    for lbl, (l, pct) in usable.items():
        if lbl in metric_names:
            continue
        slug = re.sub(r"[^a-z0-9]+", "_", lbl.lower()).strip("_") or "pool"
        pools.append(_antigravity_pool(f"antigravity_{slug}", lbl, [{
            "id": "limit",
            "label": lbl,
            "used": pct,
            "limit": 100.0,
            "remaining": _remaining(pct),
            "resetsAt": _reset_time(l),
            "resetDurationText": None
        }]))

    if not pools:
        return None

    # 平台工作馬瓶頸：主力池 (Argon 以外) 中剩餘最少者；只有 Argon 時就用 Argon
    main_pools = [p for p in pools if p["id"] not in ANTIGRAVITY_SIDE_POOLS] or pools
    governing = min(main_pools, key=lambda p: p["effectiveRemaining"])
    platform_remaining = governing["effectiveRemaining"]

    metrics = [{
        "label": metric_names.get(lbl, lbl),
        "used": _number(l.get("used")),
        "limit": _number(l.get("limit")),
        "kind": _kind(l),
        "isAlert": pct >= 90.0
    } for lbl, (l, pct) in usable.items()]

    return {
        "provider_id": "antigravity",
        "name": "Google Antigravity",
        "plan_name": c.get("plan", "Google AI Pro"),
        "total_quota": 100.0,
        "used_quota": round(100.0 - platform_remaining, 2),
        "remaining_percent": platform_remaining,
        "reset_time": governing["primaryResetTime"],
        "status": "active",
        "metrics_json": json.dumps(metrics, ensure_ascii=False),
        "token_pools_json": json.dumps(pools, ensure_ascii=False),
        "fetched_at": c.get("fetchedAt", "")
    }

def _cursor_record(c):
    total = None  # (used %, resetsAt) of the "Total usage" line
    metrics = []
    tiers = []
    for l in c.get("lines") or []:
        used_val = _percent_used(l)
        if used_val is None:
            continue
        lbl = _label(l)
        r_at = _reset_time(l)
        metrics.append({
            "label": lbl,
            "used": _number(l.get("used")),
            "limit": _number(l.get("limit")),
            "kind": _kind(l),
            "isAlert": used_val >= 90.0
        })
        tiers.append({
            "id": lbl.lower().replace(" ", "_"),
            "label": lbl,
            "used": used_val,
            "limit": 100.0,
            "remaining": _remaining(used_val),
            "resetsAt": r_at,
            "resetDurationText": "週重置" if "Total" in lbl else "即時"
        })
        if lbl == "Total usage" and total is None:
            total = (used_val, r_at)

    if total is None:
        return None
    total_used, resets_at = total
    remaining = _remaining(total_used)

    pools = [{
        "id": "cursor_main",
        "name": "Composer & Agent",
        "effectiveRemaining": remaining,
        "effectiveUsed": total_used,
        "primaryResetTime": resets_at,
        "isCritical": remaining <= 5.0,
        "tiers": tiers
    }]

    return {
        "provider_id": "cursor",
        "name": "Cursor",
        "plan_name": c.get("plan", "Premium"),
        "total_quota": 100.0,
        "used_quota": total_used,
        "remaining_percent": remaining,
        "reset_time": resets_at,
        "status": "active",
        "metrics_json": json.dumps(metrics, ensure_ascii=False),
        "token_pools_json": json.dumps(pools, ensure_ascii=False),
        "fetched_at": c.get("fetchedAt", "")
    }

def _session_weekly_record(c, provider_id, name, default_plan, pool_id, pool_name, text_value=None):
    """Codex and Claude Code: a 5h "Session" line and a "Weekly" line, governed by the tighter one."""
    session = None  # (used %, resetsAt)
    weekly = None
    metrics = []
    tiers = []
    for l in c.get("lines") or []:
        if not isinstance(l, dict):
            continue
        if l.get("type") == "progress":
            used_val = _percent_used(l)
            if used_val is None:
                continue
            lbl = _label(l)
            r_at = _reset_time(l)
            metrics.append({
                "label": lbl,
                "used": _number(l.get("used")),
                "limit": _number(l.get("limit")),
                "kind": "percent",
                "isAlert": used_val >= 90.0
            })
            tiers.append({
                "id": lbl.lower(),
                "label": f"{lbl} limit",
                "used": used_val,
                "limit": 100.0,
                "remaining": _remaining(used_val),
                "resetsAt": r_at,
                "resetDurationText": "5小時" if lbl == "Session" else "每週"
            })
            if lbl == "Session" and session is None:
                session = (used_val, r_at)
            elif lbl == "Weekly" and weekly is None:
                weekly = (used_val, r_at)
        elif l.get("type") == "text":
            val = l.get("value", "")
            metrics.append({
                "label": l.get("label", ""),
                "value": text_value(val) if text_value else val
            })

    # 最嚴格瓶頸優先 (Governing Bottleneck)：只比較快照裡真的有的週期
    governing = _governing_window(session, weekly)
    if governing is None:
        return None
    governing_used, primary_resets_at = governing
    governing_remaining = _remaining(governing_used)

    pools = [{
        "id": pool_id,
        "name": pool_name,
        "effectiveRemaining": governing_remaining,
        "effectiveUsed": governing_used,
        "primaryResetTime": primary_resets_at,
        "isCritical": governing_remaining <= 5.0,
        "tiers": tiers
    }]

    return {
        "provider_id": provider_id,
        "name": name,
        "plan_name": c.get("plan", default_plan),
        "total_quota": 100.0,
        "used_quota": governing_used,
        "remaining_percent": governing_remaining,
        "reset_time": primary_resets_at,
        "status": "active",
        "metrics_json": json.dumps(metrics, ensure_ascii=False),
        "token_pools_json": json.dumps(pools, ensure_ascii=False),
        "fetched_at": c.get("fetchedAt", "")
    }

def _codex_text(value):
    return value.replace("P", "•") if isinstance(value, str) else value

def _grok_record(c):
    weekly = None  # (used %, resetsAt) of the last progress line
    metrics = []
    for l in c.get("lines") or []:
        if not isinstance(l, dict):
            continue
        if l.get("type") == "progress":
            used_val = _percent_used(l)
            if used_val is None:
                continue
            metrics.append({
                "label": l.get("label", ""),
                "used": _number(l.get("used")),
                "limit": _number(l.get("limit")),
                "kind": "percent",
                "isAlert": used_val >= 90.0
            })
            weekly = (used_val, _reset_time(l))
        elif l.get("type") == "badge":
            metrics.append({
                "label": l.get("label", ""),
                "value": l.get("text", "")
            })

    if weekly is None:
        return None
    weekly_used, resets_at = weekly
    remaining = _remaining(weekly_used)
    metrics.append({
        "label": "Bonded Sync",
        "value": "Cursor Linked"
    })

    pools = [{
        "id": "supergrok",
        "name": "SuperGrok Quota",
        "effectiveRemaining": remaining,
        "effectiveUsed": weekly_used,
        "primaryResetTime": resets_at,
        "isCritical": remaining <= 5.0,
        "tiers": [
            {
                "id": "weekly",
                "label": "Weekly limit",
                "used": weekly_used,
                "limit": 100.0,
                "remaining": remaining,
                "resetsAt": resets_at,
                "resetDurationText": "每週"
            }
        ]
    }]

    return {
        "provider_id": "grok",
        "name": "Grok (bonded with Cursor)",
        "plan_name": c.get("plan", "SuperGrok"),
        "total_quota": 100.0,
        "used_quota": weekly_used,
        "remaining_percent": remaining,
        "reset_time": resets_at,
        "status": "active",
        "metrics_json": json.dumps(metrics, ensure_ascii=False),
        "token_pools_json": json.dumps(pools, ensure_ascii=False),
        "fetched_at": c.get("fetchedAt", "")
    }

# 上傳順序與各平台「沒有可用數據」時的略過原因
PROVIDER_BUILDERS = (
    ("cursor", _cursor_record, "快照沒有可用的 Total usage line"),
    ("codex", lambda c: _session_weekly_record(c, "codex", "Codex", "Plus", "codex_standard", "ChatGPT Plus Quota", _codex_text),
     "快照沒有可用的 Session／Weekly line"),
    ("antigravity", _antigravity_record, "快照沒有可用的額度 lines"),
    ("claude", lambda c: _session_weekly_record(c, "claude", "Claude Code", "Pro", "claude_pro", "Claude Pro Quota"),
     "快照沒有可用的 Session／Weekly line"),
    ("grok", _grok_record, "快照沒有可用的 progress line"),
)

def build_quota_records(cache_data):
    if not cache_data or "snapshots" not in cache_data:
        return []
    snapshots = cache_data["snapshots"]
    if not isinstance(snapshots, dict):
        return []

    results = []
    for provider_id, build, reason in PROVIDER_BUILDERS:
        if provider_id not in snapshots:
            continue
        c = snapshots[provider_id] if isinstance(snapshots[provider_id], dict) else {}
        record = build(c)
        if record is None:
            _skip(provider_id, reason)
        else:
            results.append(record)
    return results

def main():
    cache = load_local_cache()
    if not cache:
        print("[資訊] 未找到本機快取，略過同步。")
        return
    
    quotas = build_quota_records(cache)
    print(f"[成功] 從本機快取解析出 {len(quotas)} 筆平台真實數據 (含多配額池)：")
    for q in quotas:
        pools_info = ""
        if "token_pools_json" in q and q["token_pools_json"]:
            try:
                p_list = json.loads(q["token_pools_json"])
                pools_info = f" | 配額池: {len(p_list)} 個 ({', '.join(p['name'] + ': ' + str(int(p['effectiveRemaining'])) + '%' for p in p_list)})"
            except:
                pass
        print(f"  • {q['name']} ({q['plan_name']}): 剩餘 {q['remaining_percent']}% | 重置: {q['reset_time'] or '未知'}{pools_info}")
    
    # 若提供 API 網址，推播至邊緣服務
    if "--push" in sys.argv or os.environ.get("PUSH_TO_EDGE") == "true":
        try:
            req_data = json.dumps({"quotas": quotas}).encode("utf-8")
            req = urllib.request.Request(
                REMOTE_API_URL,
                data=req_data,
                headers={
                    "Content-Type": "application/json",
                    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) OpenTokenUsage/2.0"
                },
                method="POST"
            )
            with urllib.request.urlopen(req, timeout=10) as resp:
                res_body = json.loads(resp.read().decode("utf-8"))
                print(f"[邊緣同步成功] Cloudflare 回傳: {res_body}")
        except Exception as e:
            print(f"[邊緣同步注意] 推播至線上邊緣雲 API 未完成或連線超時: {e}")

if __name__ == "__main__":
    main()
