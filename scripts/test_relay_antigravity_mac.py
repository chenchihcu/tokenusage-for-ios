"""Tests for relay-antigravity-mac.py. Run: python3 scripts/test_relay_antigravity_mac.py"""

import copy
import importlib.util
import json
import os
import unittest
import tempfile
from pathlib import Path

_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "relay-antigravity-mac.py")
_SPEC = importlib.util.spec_from_file_location("relay_antigravity_mac", _PATH)
relay = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(relay)

# Shape of `codexbar usage --provider antigravity --format json` (CodexBar 0.84.0).
CODEXBAR_OUTPUT = [{
    "provider": "antigravity",
    "rateWindowLabels": {"primary": "Gemini Models", "secondary": "Claude and GPT"},
    "source": "app",
    "usage": {
        "accountEmail": "person@example.com",
        "extraRateWindows": [
            {"id": "antigravity-quota-summary-gemini-5h", "title": "Gemini 5-hour",
             "window": {"resetsAt": "2026-11-20T17:55:53Z", "usedPercent": 31.339645, "windowMinutes": 300}},
            {"id": "antigravity-quota-summary-gemini-weekly", "title": "Gemini weekly",
             "window": {"resetsAt": "2026-11-25T01:06:22Z", "usedPercent": 17.78473, "windowMinutes": 10080}},
            {"id": "antigravity-quota-summary-3p-5h", "title": "Claude/GPT 5-hour",
             "window": {"resetsAt": "2026-11-20T21:25:46Z", "usedPercent": 0, "windowMinutes": 300}},
            {"id": "antigravity-quota-summary-3p-weekly", "title": "Claude/GPT weekly",
             "window": {"resetsAt": "2026-11-27T16:25:46Z", "usedPercent": 0, "windowMinutes": 10080}},
            {"id": "antigravity-quota-summary-gemini-argon-wtu-weekly", "title": "Gemini 4 Argon weekly",
             "window": {"resetsAt": "2026-11-27T16:25:46Z", "usedPercent": 0, "windowMinutes": 10080}},
        ],
        "identity": {"accountEmail": "person@example.com", "loginMethod": "Google AI Pro",
                     "providerID": "antigravity"},
        "loginMethod": "Google AI Pro",
        "primary": {"resetsAt": "2026-11-20T17:55:53Z", "usedPercent": 31.339645, "windowMinutes": 300},
        "secondary": {"resetsAt": "2026-11-20T21:25:46Z", "usedPercent": 0, "windowMinutes": 300},
        "updatedAt": "2026-11-20T16:25:46Z",
    },
}]


def record_for(payload):
    return relay.build_record(relay.find_entry(payload))


class BuildRecordTests(unittest.TestCase):
    def test_groups_windows_into_antigravity_pools(self):
        record = record_for(CODEXBAR_OUTPUT)
        pools = json.loads(record["token_pools_json"])
        self.assertEqual([p["name"] for p in pools],
                         ["Gemini Models", "Claude and GPT models", "Gemini 4 Argon"])
        self.assertEqual([p["id"] for p in pools],
                         ["antigravity_gemini", "antigravity_3p", "antigravity_gemini_argon_wtu"])
        gemini = pools[0]
        self.assertEqual([t["id"] for t in gemini["tiers"]], ["5h", "weekly"])
        self.assertEqual([t["label"] for t in gemini["tiers"]], ["5 小時", "每週"])
        self.assertEqual([t["windowSeconds"] for t in gemini["tiers"]], [18000.0, 604800.0])
        self.assertEqual(gemini["tiers"][0]["used"], 31.3)  # one decimal
        # The pool is its tightest window: the 5-hour one here.
        self.assertTrue(gemini["tiers"][0]["isGoverning"])
        self.assertIsNone(gemini["tiers"][1]["isGoverning"])
        self.assertEqual(gemini["effectiveRemaining"], 68.7)
        self.assertEqual(gemini["primaryResetTime"], "2026-11-20T17:55:53Z")

    def test_headline_is_the_tightest_pool_and_keeps_the_data_time(self):
        record = record_for(CODEXBAR_OUTPUT)
        self.assertEqual(record["provider_id"], "antigravity")
        self.assertEqual(record["plan_name"], "Google AI Pro")
        self.assertEqual(record["remaining_percent"], 68.7)
        self.assertEqual(record["used_quota"], 31.3)
        self.assertEqual(record["reset_time"], "2026-11-20T17:55:53Z")
        self.assertEqual(record["status"], "active")
        self.assertEqual(record["fetched_at"], "2026-11-20T16:25:46Z")
        self.assertEqual(json.loads(record["metrics_json"]), [relay.SOURCE_METRIC])

    def test_exhausted_model_is_not_hidden(self):
        payload = copy.deepcopy(CODEXBAR_OUTPUT)
        payload[0]["usage"]["extraRateWindows"][4]["window"]["usedPercent"] = 100
        record = record_for(payload)
        self.assertEqual(record["remaining_percent"], 0)
        self.assertEqual(record["status"], "warning")
        self.assertEqual(record["reset_time"], "2026-11-27T16:25:46Z")

    def test_never_sends_the_account_email(self):
        record = record_for(CODEXBAR_OUTPUT)
        self.assertNotIn("example.com", json.dumps(record, ensure_ascii=False))

    def test_no_windows_means_nothing_to_upload(self):
        payload = copy.deepcopy(CODEXBAR_OUTPUT)
        usage = payload[0]["usage"]
        usage["extraRateWindows"] = []
        usage.pop("primary")
        usage.pop("secondary")
        self.assertIsNone(record_for(payload))
        self.assertIsNone(record_for([{"provider": "cursor", "usage": {}}]))
        self.assertIsNone(record_for({"error": "not signed in"}))

    def test_windows_without_a_percentage_are_skipped(self):
        payload = copy.deepcopy(CODEXBAR_OUTPUT)
        for extra in payload[0]["usage"]["extraRateWindows"]:
            extra["window"].pop("usedPercent")
        payload[0]["usage"].pop("primary")
        payload[0]["usage"].pop("secondary")
        self.assertIsNone(record_for(payload))

    def test_offline_placeholder_is_never_uploaded(self):
        # What CodexBar 0.84 prints when it cannot reach Antigravity (seen 2026-11-24).
        offline = [{
            "provider": "antigravity", "source": "offline",
            "diagnostic": "Live Antigravity usage is unavailable; showing offline data.",
            "usage": {
                "extraRateWindows": [{"id": "antigravity-offline-conversations", "usageKnown": False,
                                      "title": "Offline · 27 conversations", "window": {"usedPercent": 0}}],
                "identity": {"loginMethod": "offline", "providerID": "antigravity"},
                "loginMethod": "offline", "primary": None, "secondary": None,
                "updatedAt": "2026-11-24T05:55:11Z",
            },
        }]
        self.assertIsNone(record_for(offline))
        # The placeholder alone is rejected even if the source label is missing.
        offline[0].pop("source")
        self.assertIsNone(record_for(offline))

    def test_windows_without_a_length_or_marked_unknown_are_skipped(self):
        payload = copy.deepcopy(CODEXBAR_OUTPUT)
        extras = payload[0]["usage"]["extraRateWindows"]
        extras[4]["usageKnown"] = False          # Argon weekly: unknown
        extras[2]["window"].pop("windowMinutes")  # Claude/GPT 5-hour: no length
        pools = json.loads(record_for(payload)["token_pools_json"])
        self.assertEqual([p["name"] for p in pools], ["Gemini Models", "Claude and GPT models"])
        self.assertEqual([t["id"] for t in pools[1]["tiers"]], ["weekly"])

    def test_falls_back_to_primary_and_secondary(self):
        payload = copy.deepcopy(CODEXBAR_OUTPUT)
        payload[0]["usage"]["extraRateWindows"] = []
        pools = json.loads(record_for(payload)["token_pools_json"])
        self.assertEqual([p["name"] for p in pools], ["Gemini Models", "Claude and GPT"])
        self.assertEqual([len(p["tiers"]) for p in pools], [1, 1])


OFFLINE_OUTPUT = [{
    "provider": "antigravity", "source": "offline",
    "diagnostic": "Live Antigravity usage is unavailable; showing offline data. "
                  "Antigravity CSRF token not found. Restart Antigravity and retry.",
    "usage": {"extraRateWindows": [{"id": "antigravity-offline-conversations", "usageKnown": False,
                                    "window": {"usedPercent": 0}}],
              "loginMethod": "offline", "updatedAt": "2026-11-24T08:03:39Z"},
}]
# What `--source oauth` prints (exit code 1) before signing in to Antigravity in CodexBar.
OAUTH_SIGNED_OUT = [{
    "provider": "antigravity", "source": "oauth",
    "error": {"code": 1, "kind": "provider",
              "message": "Antigravity Google auth not found. Use Antigravity login to authenticate."},
}]


def reader(outputs):
    """A fake CodexBar: maps a source (None = default) to its output or an exception."""
    calls = []

    def read(source):
        calls.append(source)
        result = outputs[source]
        if isinstance(result, Exception):
            raise result
        return copy.deepcopy(result)
    return read, calls


class ReadLiveTests(unittest.TestCase):
    def test_default_source_with_live_quota_is_used_alone(self):
        read, calls = reader({None: CODEXBAR_OUTPUT})
        record, reasons, failed = relay.read_live(read)
        self.assertEqual(record["remaining_percent"], 68.7)
        self.assertEqual((reasons, failed, calls), ([], False, [None]))

    def test_offline_default_falls_back_to_oauth(self):
        oauth = copy.deepcopy(CODEXBAR_OUTPUT)
        oauth[0]["source"] = "oauth"
        read, calls = reader({None: OFFLINE_OUTPUT, "oauth": oauth})
        record, reasons, failed = relay.read_live(read)
        self.assertEqual(calls, [None, "oauth"])
        self.assertEqual(record["remaining_percent"], 68.7)
        self.assertEqual((reasons, failed), ([], False))

    def test_nothing_live_reports_both_reasons(self):
        read, _ = reader({None: OFFLINE_OUTPUT, "oauth": OAUTH_SIGNED_OUT})
        record, reasons, failed = relay.read_live(read)
        self.assertIsNone(record)
        self.assertFalse(failed)
        self.assertIn("CSRF token not found", reasons[0])
        self.assertTrue(reasons[1].startswith("oauth: Antigravity Google auth not found"))

    def test_unreadable_codexbar_is_a_read_failure(self):
        read, _ = reader({None: RuntimeError("CodexBar exited 1: boom"), "oauth": OSError("gone")})
        record, reasons, failed = relay.read_live(read)
        self.assertIsNone(record)
        self.assertTrue(failed)
        self.assertEqual(len(reasons), 2)

    def test_one_unreadable_source_is_not_a_read_failure(self):
        read, _ = reader({None: OFFLINE_OUTPUT, "oauth": RuntimeError("timeout")})
        _, _, failed = relay.read_live(read)
        self.assertFalse(failed)


class RefreshPollingTests(unittest.TestCase):
    def test_request_triggers_a_single_early_measurement(self):
        import io
        from unittest.mock import patch

        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory) / "state.json"
            state.write_text('{"attempted_at": 1000}')
            url = "https://example.com/api/quotas/sync"
            ticket = b'{"requested_at":"2026-11-25T13:40:00.000Z"}'
            with patch("time.time", return_value=1020), patch.object(relay, "main", return_value=0) as measure:
                with patch.object(relay.urllib.request, "urlopen", side_effect=[io.BytesIO(ticket), io.BytesIO(ticket)]) as poll:
                    self.assertEqual(relay.poll_refresh(url, "upload-key", state), 0)
                    self.assertEqual(relay.poll_refresh(url, "upload-key", state), 0)
                    measure.assert_called_once_with([])
                    request = poll.call_args.args[0]
                    self.assertEqual(request.full_url, "https://example.com/api/antigravity/refresh")
                    self.assertEqual(request.get_header("Authorization"), "Bearer upload-key")
                    self.assertEqual(request.get_header("User-agent"), relay.RELAY_USER_AGENT)

    def test_worker_outage_preserves_scheduled_measurement(self):
        from unittest.mock import patch

        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory) / "state.json"
            with patch.object(relay, "main", return_value=0) as measure:
                with patch.object(relay.urllib.request, "urlopen", side_effect=OSError("offline")):
                    self.assertEqual(relay.poll_refresh("https://example.com/api/quotas/sync", "key", state), 0)
                    measure.assert_called_once_with([])


if __name__ == "__main__":
    unittest.main(verbosity=2)
