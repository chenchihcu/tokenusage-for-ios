"""Checks that sync-desktop-accounts.py uploads only figures found in the desktop cache.

Run: python -I -m pytest scripts/tests
"""

import copy
import importlib.util
import json
import os
import re

import pytest

SCRIPT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "sync-desktop-accounts.py")
RECORD_KEYS = {
    "provider_id", "name", "plan_name", "total_quota", "used_quota", "remaining_percent",
    "reset_time", "status", "metrics_json", "token_pools_json", "fetched_at",
}


def _load_module():
    spec = importlib.util.spec_from_file_location("sync_desktop_accounts", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


sync = _load_module()


def progress(label, used, resets_at=None, limit=100):
    line = {"type": "progress", "label": label, "used": used, "limit": limit, "format": {"kind": "percent"}}
    if resets_at:
        line["resetsAt"] = resets_at
    return line


# Figures deliberately differ from the old hard-coded ones (69 / 5 / 54 / 0 / 100).
ANTIGRAVITY_LINES = [
    progress("Session", 12.5, "2030-01-01T05:00:00Z"),
    progress("Weekly", 40, "2030-01-03T10:00:00Z"),
    progress("Argon Weekly", 20, "2030-01-04T09:00:00Z"),
    progress("Claude", 7),
    progress("Claude Weekly", 61, "2030-01-05T08:00:00Z"),
]

SAMPLE_CACHE = {
    "snapshots": {
        "antigravity": {"plan": "Google AI Ultra", "fetchedAt": "2030-01-01T00:00:00Z", "lines": ANTIGRAVITY_LINES},
        "cursor": {"lines": [progress("Total usage", 33, "2030-02-01T00:00:00Z"), {"type": "badge", "label": "Plan", "text": "Pro"}]},
        "codex": {"lines": [progress("Session", 10, "2030-01-01T03:00:00Z"), progress("Weekly", 25, "2030-01-06T00:00:00Z")]},
        "claude": {"lines": [progress("Session", 80, "2030-01-01T04:00:00Z"), progress("Weekly", 30)]},
        "grok": {"lines": [progress("Weekly", 45, "2030-01-07T00:00:00Z")]},
    }
}


@pytest.fixture
def cache_file(tmp_path, monkeypatch):
    """Writes a usage-api-cache.json and points the script at it."""

    def write(cache):
        path = tmp_path / "usage-api-cache.json"
        path.write_text(json.dumps(cache), encoding="utf-8")
        monkeypatch.setattr(sync, "CACHE_PATH", str(path))
        return sync.build_quota_records(sync.load_local_cache())

    return write


def by_id(records):
    return {r["provider_id"]: r for r in records}


def test_antigravity_record_matches_the_cache_lines(cache_file):
    record = by_id(cache_file(SAMPLE_CACHE))["antigravity"]
    pools = {p["id"]: p for p in json.loads(record["token_pools_json"])}

    assert list(pools) == ["gemini_models", "claude_gpt", "gemini_4_argon"]

    gemini = {t["id"]: t for t in pools["gemini_models"]["tiers"]}
    assert (gemini["weekly"]["used"], gemini["weekly"]["remaining"], gemini["weekly"]["resetsAt"]) == (40.0, 60.0, "2030-01-03T10:00:00Z")
    assert (gemini["5h"]["used"], gemini["5h"]["remaining"], gemini["5h"]["resetsAt"]) == (12.5, 87.5, "2030-01-01T05:00:00Z")
    assert pools["gemini_models"]["effectiveRemaining"] == 60.0
    assert pools["gemini_models"]["primaryResetTime"] == "2030-01-03T10:00:00Z"
    assert gemini["weekly"]["isGoverning"] is True and gemini["5h"]["isGoverning"] is False

    claude = {t["id"]: t for t in pools["claude_gpt"]["tiers"]}
    assert (claude["weekly"]["used"], claude["weekly"]["resetsAt"]) == (61.0, "2030-01-05T08:00:00Z")
    assert (claude["5h"]["used"], claude["5h"]["resetsAt"]) == (7.0, None)

    argon = pools["gemini_4_argon"]
    assert (argon["effectiveRemaining"], argon["primaryResetTime"], argon["isCritical"]) == (80.0, "2030-01-04T09:00:00Z", False)

    # Platform figure: tightest workhorse pool (Claude & GPT weekly, 61 % used); Argon is left out.
    assert record["remaining_percent"] == 39.0
    assert record["used_quota"] == 61.0
    assert record["reset_time"] == "2030-01-05T08:00:00Z"
    assert record["plan_name"] == "Google AI Ultra"
    assert record["fetched_at"] == "2030-01-01T00:00:00Z"

    metrics = {m["label"]: m["used"] for m in json.loads(record["metrics_json"])}
    assert metrics == {"Gemini (5h)": 12.5, "Gemini (週)": 40.0, "Argon": 20.0, "Claude (5h)": 7.0, "Claude (週)": 61.0}


@pytest.mark.parametrize("snapshot", [
    {},
    {"lines": []},
    {"lines": [{"type": "text", "label": "Status", "value": "signed out"}]},
    {"lines": [{"type": "progress", "label": "Weekly"}, {"type": "progress", "label": "Session", "used": "n/a", "limit": 100}]},
    None,
])
def test_antigravity_without_usable_lines_uploads_nothing(cache_file, snapshot):
    cache = copy.deepcopy(SAMPLE_CACHE)
    cache["snapshots"]["antigravity"] = snapshot
    records = by_id(cache_file(cache))
    assert "antigravity" not in records
    assert set(records) == {"cursor", "codex", "claude", "grok"}


def test_antigravity_keeps_only_the_windows_it_was_given(cache_file):
    cache = {"snapshots": {"antigravity": {"lines": [progress("Weekly", 55)]}}}
    record = by_id(cache_file(cache))["antigravity"]
    pools = json.loads(record["token_pools_json"])

    assert [p["id"] for p in pools] == ["gemini_models"]
    assert [(t["id"], t["used"], t["resetsAt"]) for t in pools[0]["tiers"]] == [("weekly", 55.0, None)]
    assert (record["remaining_percent"], record["reset_time"]) == (45.0, None)


def test_antigravity_unknown_label_becomes_its_own_pool(cache_file):
    cache = {"snapshots": {"antigravity": {"lines": [progress("Weekly", 10), progress("Gemini 5 Nova", 30, "2030-03-01T00:00:00Z")]}}}
    pools = {p["id"]: p for p in json.loads(by_id(cache_file(cache))["antigravity"]["token_pools_json"])}

    assert set(pools) == {"gemini_models", "antigravity_gemini_5_nova"}
    nova = pools["antigravity_gemini_5_nova"]
    assert (nova["name"], nova["effectiveRemaining"], nova["primaryResetTime"]) == ("Gemini 5 Nova", 70.0, "2030-03-01T00:00:00Z")


def test_other_providers_send_no_default_dates_or_figures(cache_file):
    cache = {"snapshots": {
        "cursor": {"lines": [progress("Total usage", 20)]},
        "codex": {"lines": [progress("Session", 15)]},
        "claude": {"lines": [progress("Weekly", 5)]},
        "grok": {"lines": [progress("Weekly", 50)]},
    }}
    records = by_id(cache_file(cache))

    for provider_id, used in {"cursor": 20.0, "codex": 15.0, "claude": 5.0, "grok": 50.0}.items():
        record = records[provider_id]
        assert record["reset_time"] is None, provider_id
        assert record["used_quota"] == used, provider_id
        assert all(p["primaryResetTime"] is None for p in json.loads(record["token_pools_json"])), provider_id
    assert json.loads(records["grok"]["token_pools_json"])[0]["isCritical"] is False


def test_providers_without_headline_lines_upload_nothing(cache_file):
    cache = {"snapshots": {
        "cursor": {"lines": [{"type": "badge", "label": "Plan", "text": "Pro"}]},
        "codex": {"lines": [{"type": "text", "label": "Credits", "value": "0"}]},
        "claude": {"lines": []},
        "grok": {},
    }}
    assert cache_file(cache) == []


def test_upload_payload_shape_is_unchanged(cache_file):
    records = cache_file(SAMPLE_CACHE)
    assert [r["provider_id"] for r in records] == ["cursor", "codex", "antigravity", "claude", "grok"]
    for record in records:
        assert set(record) == RECORD_KEYS
        assert isinstance(json.loads(record["metrics_json"]), list)
        assert isinstance(json.loads(record["token_pools_json"]), list)


def test_script_has_no_hard_coded_dates_or_usage_figures():
    with open(SCRIPT, encoding="utf-8") as f:
        source = f.read()
    assert not re.search(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}", source)
    assert not re.search(r'"(used|remaining|effectiveRemaining|effectiveUsed)":\s*-?\d', source)
    assert not re.search(r"(total_used|weekly_used|session_used)\s*=\s*\d", source)
