"""Tests for relay-antigravity-mac.py. Run: python3 scripts/test_relay_antigravity_mac.py"""

import copy
import importlib.util
import json
import os
import unittest

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


if __name__ == "__main__":
    unittest.main(verbosity=2)
