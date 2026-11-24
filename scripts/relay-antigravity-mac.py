#!/usr/bin/env python3
"""Relay Google Antigravity usage from this Mac to the OpenTokenUsage Worker.

Google does not let the iPhone app sign in to Antigravity. This Mac can already read
Antigravity usage through CodexBar (`codexbar usage --provider antigravity`), so this
script turns that reading into one `provider_quotas` row and uploads it to the Worker
(`POST /api/quotas/sync`). The iPhone app reads it back from `GET /api/quotas`.

Nothing is invented: when CodexBar returns no Antigravity windows, nothing is uploaded.
The account e-mail that CodexBar reports is never sent.

Usage:
  python3 relay-antigravity-mac.py            read CodexBar and upload
  python3 relay-antigravity-mac.py --dry-run  print the row instead of uploading

Environment:
  SYNC_API_URL  upload endpoint (default: the project's Worker)
  SYNC_TOKEN    sent as "Authorization: Bearer ..." (the Worker secret of the same name);
                when unset, ~/.config/opentokenusage/sync_token is used if it exists
  CODEXBAR_BIN  path to the CodexBar CLI (default: found on PATH or in CodexBar.app)

Exit codes: 0 uploaded (or printed), 1 CodexBar or upload failed, 2 no Antigravity data.
"""

import argparse
import datetime
import json
import os
import shutil
import subprocess
import sys
import urllib.error
import urllib.request

DEFAULT_SYNC_URL = "https://opentokenusage-web.chihfu-chen-tw.workers.dev/api/quotas/sync"
TOKEN_FILE = os.path.expanduser("~/.config/opentokenusage/sync_token")
CODEXBAR_CANDIDATES = (
    "/opt/homebrew/bin/codexbar",
    "/usr/local/bin/codexbar",
    "/Applications/CodexBar.app/Contents/Helpers/CodexBarCLI",
)

# The phone shows only rows carrying this marker, so seed or placeholder rows already in
# the database never appear as real figures. Must match AntigravityRelay in the iOS app.
SOURCE_METRIC = {"label": "來源", "value": "Mac 轉送（CodexBar）"}

WINDOW_PREFIX = "antigravity-quota-summary-"
# CodexBar window ids look like "antigravity-quota-summary-<group>-<5h|weekly>".
KNOWN_GROUPS = {
    "gemini": ("antigravity_gemini", "Gemini Models", "Gemini 模型共用這些限制。"),
    "3p": ("antigravity_3p", "Claude and GPT models", "Claude 與 GPT 模型共用這些限制。"),
}
TITLE_SUFFIXES = (" 5-hour", " weekly", " 5h", " session")


def _number(value):
    if isinstance(value, bool):
        return None
    if isinstance(value, (int, float)):
        return float(value)
    if isinstance(value, str):
        try:
            return float(value)
        except ValueError:
            return None
    return None


def _window_label(minutes):
    if minutes == 300:
        return "5 小時"
    if minutes == 10080:
        return "每週"
    if minutes == 1440:
        return "每日"
    if minutes and minutes >= 1440:
        return "%d 天" % (minutes // 1440)
    if minutes and minutes >= 60:
        return "%d 小時" % (minutes // 60)
    return "用量"


def _tier(window, fallback_id, usage_known=True):
    """One CodexBar window as a QuotaTier (same fields the iOS app decodes), or None when it is
    not a measured quota window: CodexBar marks placeholders `usageKnown: false` (for example
    "Offline · 27 conversations" at 0 %), and a real quota window always has a length."""
    if usage_known is False or window.get("usageKnown") is False:
        return None
    used = _number(window.get("usedPercent"))
    minutes = _number(window.get("windowMinutes"))
    if used is None or not minutes or minutes <= 0:
        return None
    # One decimal, as the vendor shows it; the website prints these numbers as they are.
    used = round(min(max(used, 0.0), 100.0), 1)
    minutes = int(minutes)
    tier_id = {300: "5h", 10080: "weekly"}.get(minutes, fallback_id)
    return {
        "id": tier_id,
        "label": _window_label(minutes),
        "used": used,
        "limit": 100.0,
        "remaining": round(100.0 - used, 1),
        "resetsAt": window.get("resetsAt"),
        "windowSeconds": float(minutes * 60),
    }


def _group_of(window_id, title):
    """(pool id, pool name, description) for a CodexBar extra window."""
    rest = window_id[len(WINDOW_PREFIX):] if window_id.startswith(WINDOW_PREFIX) else window_id
    group = rest.rsplit("-", 1)[0] if "-" in rest else rest
    if group in KNOWN_GROUPS:
        return KNOWN_GROUPS[group]
    name = title or group
    for suffix in TITLE_SUFFIXES:
        if name.lower().endswith(suffix):
            name = name[: -len(suffix)]
            break
    return ("antigravity_" + group.replace("-", "_"), name.strip() or group, None)


def _pool(pool_id, name, description, tiers):
    """Same rule as QuotaAssembly.make on the phone: a pool is its tightest window."""
    worst = min(range(len(tiers)), key=lambda i: tiers[i]["remaining"])
    for i, tier in enumerate(tiers):
        tier["isGoverning"] = True if i == worst else None
    remaining = tiers[worst]["remaining"]
    return {
        "id": pool_id,
        "name": name,
        "description": description,
        "effectiveRemaining": remaining,
        "effectiveUsed": round(100.0 - remaining, 1),
        "primaryResetTime": tiers[worst]["resetsAt"],
        "isCritical": remaining <= 5,
        "tiers": tiers,
    }


def build_pools(usage, labels):
    pools = []  # keeps CodexBar's order
    index = {}
    for extra in usage.get("extraRateWindows") or []:
        window = extra.get("window") or {}
        window_id = str(extra.get("id") or "")
        pool_id, name, description = _group_of(window_id, str(extra.get("title") or ""))
        tier = _tier(window, fallback_id=window_id.rsplit("-", 1)[-1] or "window",
                     usage_known=extra.get("usageKnown"))
        if tier is None:
            continue
        if pool_id not in index:
            index[pool_id] = len(pools)
            pools.append((pool_id, name, description, []))
        pools[index[pool_id]][3].append(tier)

    if not pools:
        # Older CodexBar output: one window per group under primary / secondary.
        for slot in ("primary", "secondary"):
            window = usage.get(slot)
            name = (labels or {}).get(slot)
            if not isinstance(window, dict) or not name:
                continue
            tier = _tier(window, fallback_id=slot)
            if tier is not None:
                pools.append(("antigravity_" + slot, name, None, [tier]))

    return [_pool(pid, name, desc, tiers) for pid, name, desc, tiers in pools if tiers]


def build_record(entry, now=None):
    """The Worker row for one CodexBar Antigravity entry, or None when it has no windows."""
    if not isinstance(entry, dict) or entry.get("provider") != "antigravity":
        return None
    # "offline" means CodexBar could not read live quota and shows cached placeholders.
    if str(entry.get("source") or "").lower() == "offline":
        return None
    usage = entry.get("usage")
    if not isinstance(usage, dict):
        return None
    pools = build_pools(usage, entry.get("rateWindowLabels"))
    if not pools:
        return None
    tightest = min(pools, key=lambda p: p["effectiveRemaining"])
    remaining = tightest["effectiveRemaining"]
    identity = usage.get("identity") if isinstance(usage.get("identity"), dict) else {}
    plan = usage.get("loginMethod") or identity.get("loginMethod") or "Google Antigravity"
    now = now or datetime.datetime.now(datetime.timezone.utc)
    fetched = usage.get("updatedAt") or now.strftime("%Y-%m-%dT%H:%M:%SZ")
    return {
        "provider_id": "antigravity",
        "name": "Google Antigravity",
        "plan_name": str(plan),
        "total_quota": 100.0,
        "used_quota": round(100.0 - remaining, 1),
        "remaining_percent": remaining,
        "reset_time": tightest["primaryResetTime"] or "",
        "status": "warning" if remaining <= 5 else "active",
        "metrics_json": json.dumps([SOURCE_METRIC], ensure_ascii=False),
        "token_pools_json": json.dumps(pools, ensure_ascii=False),
        "fetched_at": fetched,
    }


def find_entry(payload):
    entries = payload if isinstance(payload, list) else [payload]
    for entry in entries:
        if isinstance(entry, dict) and entry.get("provider") == "antigravity":
            return entry
    return None


def find_codexbar():
    configured = os.environ.get("CODEXBAR_BIN")
    if configured:
        return configured
    on_path = shutil.which("codexbar")
    if on_path:
        return on_path
    for candidate in CODEXBAR_CANDIDATES:
        if os.access(candidate, os.X_OK):
            return candidate
    return None


def read_codexbar(binary):
    result = subprocess.run(
        [binary, "usage", "--provider", "antigravity", "--format", "json"],
        capture_output=True, text=True, timeout=90,
    )
    if result.returncode != 0:
        raise RuntimeError("CodexBar exited %d: %s" % (result.returncode, result.stderr.strip()[-300:]))
    return json.loads(result.stdout)


def sync_token():
    token = os.environ.get("SYNC_TOKEN", "").strip()
    if token:
        return token
    try:
        with open(TOKEN_FILE, "r", encoding="utf-8") as handle:
            return handle.read().strip()
    except OSError:
        return ""


def upload(record, url, token):
    body = json.dumps({"quotas": [record]}, ensure_ascii=False).encode("utf-8")
    request = urllib.request.Request(url, data=body, method="POST")
    request.add_header("Content-Type", "application/json")
    request.add_header("User-Agent", "OpenTokenUsage-antigravity-relay/1")
    if token:
        request.add_header("Authorization", "Bearer " + token)
    with urllib.request.urlopen(request, timeout=20) as response:
        return response.status, response.read().decode("utf-8", "replace")[:300]


def main(argv=None):
    parser = argparse.ArgumentParser(description="Relay Antigravity usage to the OpenTokenUsage Worker.")
    parser.add_argument("--dry-run", action="store_true", help="print the row instead of uploading")
    parser.add_argument("--from-file", help="read CodexBar JSON from this file instead of running CodexBar")
    args = parser.parse_args(argv)
    stamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    try:
        if args.from_file:
            with open(args.from_file, "r", encoding="utf-8") as handle:
                payload = json.load(handle)
        else:
            binary = find_codexbar()
            if not binary:
                print("%s CodexBar CLI not found; set CODEXBAR_BIN." % stamp, file=sys.stderr)
                return 1
            payload = read_codexbar(binary)
    except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired) as error:
        print("%s Could not read CodexBar: %s" % (stamp, error), file=sys.stderr)
        return 1

    entry = find_entry(payload)
    record = build_record(entry)
    if record is None:
        why = (entry or {}).get("diagnostic") or "no measured Antigravity quota windows"
        print("%s Nothing uploaded: %s" % (stamp, why), file=sys.stderr)
        return 2

    if args.dry_run:
        print(json.dumps({"quotas": [record]}, ensure_ascii=False, indent=2))
        return 0

    url = os.environ.get("SYNC_API_URL", DEFAULT_SYNC_URL)
    try:
        status, text = upload(record, url, sync_token())
    except urllib.error.HTTPError as error:
        print("%s Upload refused (%d): %s" % (stamp, error.code, error.read().decode("utf-8", "replace")[:200]),
              file=sys.stderr)
        return 1
    except (urllib.error.URLError, OSError) as error:
        print("%s Upload failed: %s" % (stamp, error), file=sys.stderr)
        return 1
    print("%s Uploaded Antigravity (%.0f%% left, data %s): HTTP %d %s"
          % (stamp, record["remaining_percent"], record["fetched_at"], status, text))
    return 0


if __name__ == "__main__":
    sys.exit(main())
