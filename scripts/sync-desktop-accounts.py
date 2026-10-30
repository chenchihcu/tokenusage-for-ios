#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
OpenTokenUsage 本機快取真實帳號同步腳本 (Desktop SSOT Sync)
讀取 %APPDATA%/com.poweruserz.opentokenusage/usage-api-cache.json
並將 5 大專屬平台 (Cursor, Codex, Antigravity, Claude Code, Grok) 的最新真實數據
同步至 D1 資料庫或線上 Edge Worker API。
"""

import os
import sys
import json
import urllib.request
import urllib.error

CACHE_PATH = os.path.expandvars(r"%APPDATA%\com.poweruserz.opentokenusage\usage-api-cache.json")
REMOTE_API_URL = os.environ.get("SYNC_API_URL", "https://opentokenusage-web.chihfu-chen-tw.workers.dev/api/quotas/sync")

def load_local_cache():
    if not os.path.exists(CACHE_PATH):
        print(f"[警告] 找不到本機快取檔案: {CACHE_PATH}，將使用基準結構")
        return None
    with open(CACHE_PATH, "r", encoding="utf-8") as f:
        return json.load(f)

def build_quota_records(cache_data):
    if not cache_data or "snapshots" not in cache_data:
        return []
    
    snapshots = cache_data["snapshots"]
    results = []

    # 1. Cursor
    if "cursor" in snapshots:
        c = snapshots["cursor"]
        lines = c.get("lines", [])
        total_used = 100.0
        resets_at = "2026-11-03T12:12:52.768Z"
        metrics = []
        for l in lines:
            metrics.append({
                "label": l.get("label", ""),
                "used": l.get("used", 0.0),
                "limit": l.get("limit", 100.0),
                "kind": l.get("format", {}).get("kind", "percent"),
                "isAlert": l.get("used", 0) >= 90.0
            })
            if l.get("label") == "Total usage":
                total_used = l.get("used", 100.0)
                resets_at = l.get("resetsAt", resets_at)
        
        results.append({
            "provider_id": "cursor",
            "name": "Cursor",
            "plan_name": c.get("plan", "Premium"),
            "total_quota": 100.0,
            "used_quota": total_used,
            "remaining_percent": max(0.0, 100.0 - total_used),
            "reset_time": resets_at,
            "status": "active",
            "metrics_json": json.dumps(metrics, ensure_ascii=False),
            "fetched_at": c.get("fetchedAt", "")
        })

    # 2. Codex
    if "codex" in snapshots:
        c = snapshots["codex"]
        lines = c.get("lines", [])
        session_used = 0.0
        resets_at = "2026-11-04T06:48:16.000Z"
        metrics = []
        for l in lines:
            if l.get("type") == "progress":
                metrics.append({
                    "label": l.get("label", ""),
                    "used": l.get("used", 0.0),
                    "limit": l.get("limit", 100.0),
                    "kind": "percent",
                    "isAlert": l.get("label") == "Weekly" and l.get("used", 0) >= 90.0
                })
                if l.get("label") == "Session":
                    session_used = l.get("used", 0.0)
                elif l.get("label") == "Weekly":
                    resets_at = l.get("resetsAt", resets_at)
            elif l.get("type") == "text":
                val = l.get("value", "")
                metrics.append({
                    "label": l.get("label", ""),
                    "value": val.replace("P", "•")
                })
        
        results.append({
            "provider_id": "codex",
            "name": "Codex",
            "plan_name": c.get("plan", "Plus"),
            "total_quota": 100.0,
            "used_quota": session_used,
            "remaining_percent": max(0.0, 100.0 - session_used),
            "reset_time": resets_at,
            "status": "active",
            "metrics_json": json.dumps(metrics, ensure_ascii=False),
            "fetched_at": c.get("fetchedAt", "")
        })

    # 3. Google Antigravity
    if "antigravity" in snapshots:
        c = snapshots["antigravity"]
        lines = c.get("lines", [])
        session_used = 8.0
        resets_at = "2026-10-30T23:29:29Z"
        metrics = []
        for l in lines:
            metrics.append({
                "label": l.get("label", ""),
                "used": l.get("used", 0.0),
                "limit": l.get("limit", 100.0),
                "kind": "percent"
            })
            if l.get("label") == "Session":
                session_used = l.get("used", 8.0)
                resets_at = l.get("resetsAt", resets_at)
        
        results.append({
            "provider_id": "antigravity",
            "name": "Google Antigravity",
            "plan_name": c.get("plan", "Google AI Pro"),
            "total_quota": 100.0,
            "used_quota": session_used,
            "remaining_percent": max(0.0, 100.0 - session_used),
            "reset_time": resets_at,
            "status": "active",
            "metrics_json": json.dumps(metrics, ensure_ascii=False),
            "fetched_at": c.get("fetchedAt", "")
        })

    # 4. Claude Code
    if "claude" in snapshots:
        c = snapshots["claude"]
        lines = c.get("lines", [])
        session_used = 0.0
        resets_at = "2026-11-02T12:59:59.805Z"
        metrics = []
        for l in lines:
            if l.get("type") == "progress":
                metrics.append({
                    "label": l.get("label", ""),
                    "used": l.get("used", 0.0),
                    "limit": l.get("limit", 100.0),
                    "kind": "percent",
                    "isAlert": l.get("label") == "Weekly" and l.get("used", 0) >= 90.0
                })
                if l.get("label") == "Session":
                    session_used = l.get("used", 0.0)
                elif l.get("label") == "Weekly":
                    resets_at = l.get("resetsAt", resets_at)
            elif l.get("type") == "text":
                metrics.append({
                    "label": l.get("label", ""),
                    "value": l.get("value", "")
                })

        results.append({
            "provider_id": "claude",
            "name": "Claude Code",
            "plan_name": c.get("plan", "Pro"),
            "total_quota": 100.0,
            "used_quota": session_used,
            "remaining_percent": max(0.0, 100.0 - session_used),
            "reset_time": resets_at,
            "status": "active",
            "metrics_json": json.dumps(metrics, ensure_ascii=False),
            "fetched_at": c.get("fetchedAt", "")
        })

    # 5. Grok (bonded with Cursor)
    if "grok" in snapshots:
        c = snapshots["grok"]
        lines = c.get("lines", [])
        weekly_used = 100.0
        resets_at = "2026-11-03T12:12:52.768Z"
        metrics = []
        for l in lines:
            if l.get("type") == "progress":
                metrics.append({
                    "label": l.get("label", ""),
                    "used": l.get("used", 100.0),
                    "limit": l.get("limit", 100.0),
                    "kind": "percent",
                    "isAlert": True
                })
                weekly_used = l.get("used", 100.0)
                resets_at = l.get("resetsAt", resets_at)
            elif l.get("type") == "badge":
                metrics.append({
                    "label": l.get("label", ""),
                    "value": l.get("text", "")
                })
        metrics.append({
            "label": "Bonded Sync",
            "value": "Cursor Linked"
        })

        results.append({
            "provider_id": "grok",
            "name": "Grok (bonded with Cursor)",
            "plan_name": c.get("plan", "SuperGrok"),
            "total_quota": 100.0,
            "used_quota": weekly_used,
            "remaining_percent": max(0.0, 100.0 - weekly_used),
            "reset_time": resets_at,
            "status": "active",
            "metrics_json": json.dumps(metrics, ensure_ascii=False),
            "fetched_at": c.get("fetchedAt", "")
        })

    return results

def main():
    cache = load_local_cache()
    if not cache:
        print("[資訊] 未找到本機快取，略過同步。")
        return
    
    quotas = build_quota_records(cache)
    print(f"[成功] 從本機快取解析出 {len(quotas)} 筆平台真實數據：")
    for q in quotas:
        print(f"  • {q['name']} ({q['plan_name']}): 剩餘 {q['remaining_percent']}% | 重置: {q['reset_time']}")
    
    # 若提供 API 網址，推播至邊緣服務
    if "--push" in sys.argv or os.environ.get("PUSH_TO_EDGE") == "true":
        try:
            req_data = json.dumps({"quotas": quotas}).encode("utf-8")
            req = urllib.request.Request(
                REMOTE_API_URL,
                data=req_data,
                headers={"Content-Type": "application/json"},
                method="POST"
            )
            with urllib.request.urlopen(req, timeout=10) as resp:
                res_body = json.loads(resp.read().decode("utf-8"))
                print(f"[邊緣同步成功] Cloudflare 回傳: {res_body}")
        except Exception as e:
            print(f"[邊緣同步注意] 推播至線上邊緣雲 API 未完成或連線超時: {e}")

if __name__ == "__main__":
    main()
