#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
OpenTokenUsage 本機零接觸自適應同步守護進程 (Zero-Touch Desktop Sync Daemon)
監聽 %APPDATA%/com.poweruserz.opentokenusage/usage-api-cache.json 檔案異動，
具備連線感知 (Network-Aware Probe) 與 2 秒防抖 (Debounce)，在有網路連線時
自動將最新數據推送至 Cloudflare Edge Worker 與 D1。
"""

import os
import sys
import time
import json
import hashlib
import urllib.request
import urllib.error

import importlib.util

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
LOG_FILE = os.path.join(SCRIPT_DIR, "sync-daemon.log")

# 確保在 Windows 靜默背景執行 (無終端 Console) 時 stdout 不會崩潰，並記錄至 log 檔
class LoggerWriter:
    def __init__(self, filepath):
        self.filepath = filepath
        self.terminal = sys.stdout

    def write(self, message):
        if self.terminal:
            try:
                self.terminal.write(message)
            except Exception:
                pass
        try:
            with open(self.filepath, "a", encoding="utf-8") as f:
                f.write(message)
        except Exception:
            pass

    def flush(self):
        if self.terminal:
            try:
                self.terminal.flush()
            except Exception:
                pass

sys.stdout = LoggerWriter(LOG_FILE)
sys.stderr = sys.stdout

# 動態加載同目錄下的核心轉換腳本 (避免檔名連字號限制)
CORE_PATH = os.path.join(SCRIPT_DIR, "sync-desktop-accounts.py")
spec = importlib.util.spec_from_file_location("sync_core", CORE_PATH)
sync_core = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sync_core)

CACHE_PATH = os.path.expandvars(r"%APPDATA%\com.poweruserz.opentokenusage\usage-api-cache.json")
REMOTE_API_URL = os.environ.get("SYNC_API_URL", "https://opentokenusage-web.chihfu-chen-tw.workers.dev/api/quotas/sync")
CHECK_INTERVAL_SEC = 2.0  # 檔案異動探測頻率 (秒)
DEBOUNCE_SEC = 2.0        # 防抖時間窗口 (秒)

def get_file_hash(path):
    if not os.path.exists(path):
        return None
    try:
        with open(path, "rb") as f:
            return hashlib.sha256(f.read()).hexdigest()
    except Exception:
        return None

def is_network_online():
    """超輕量連線探針：測試是否能連線至邊緣服務端點"""
    try:
        req = urllib.request.Request(
            "https://opentokenusage-web.chihfu-chen-tw.workers.dev/api/quotas",
            headers={"User-Agent": "OpenTokenUsage-SyncDaemon/2.0"}
        )
        with urllib.request.urlopen(req, timeout=3) as resp:
            return resp.status in (200, 304)
    except Exception:
        return False

def push_to_edge(records):
    """執行推送至 Edge Worker"""
    payload = json.dumps({"quotas": records}, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(
        REMOTE_API_URL,
        data=payload,
        headers=sync_core.upload_headers("OpenTokenUsage-SyncDaemon/2.0"),
        method="POST"
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            result = json.loads(resp.read().decode("utf-8"))
            return result.get("success", False)
    except Exception as e:
        print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] [守護進程] 推送失敗: {e}")
        return False

def main():
    run_once = "--once" in sys.argv
    print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] [守護進程啟動] 模式: {'單次檢查' if run_once else '持續監聽'} | 目標: {CACHE_PATH}")
    last_hash = get_file_hash(CACHE_PATH)
    pending_sync = False
    last_change_time = 0.0

    # 首次啟動若有快取，先執行一次初始同步
    if last_hash and is_network_online():
        try:
            cache = sync_core.load_local_cache()
            recs = sync_core.build_quota_records(cache)
            if recs:
                if push_to_edge(recs):
                    print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] [守護進程] 初始同步成功 ({len(recs)} 筆)")
        except Exception as e:
            print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] [守護進程] 初始同步異常: {e}")

    if run_once:
        print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] [守護進程] 單次模式執行完畢")
        return

    while True:
        try:
            time.sleep(CHECK_INTERVAL_SEC)
            current_hash = get_file_hash(CACHE_PATH)

            if current_hash and current_hash != last_hash:
                last_hash = current_hash
                pending_sync = True
                last_change_time = time.time()
                print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] [快取異動] 偵測到桌面端寫入，啟動 2 秒防抖計時...")

            # 防抖窗口期過後，且有網路連線時執行推送
            if pending_sync and (time.time() - last_change_time >= DEBOUNCE_SEC):
                if is_network_online():
                    cache = sync_core.load_local_cache()
                    recs = sync_core.build_quota_records(cache)
                    if recs and push_to_edge(recs):
                        print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] [同步完成] 成功自動推送 {len(recs)} 筆至雲端 D1")
                        pending_sync = False
                    else:
                        print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] [同步暫停] 推送未成功，將於下個週期重試")
                else:
                    print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] [離線感知] 當前無網路連線，資料已暫存待傳佇列")

        except KeyboardInterrupt:
            print(f"\n[{time.strftime('%Y-%m-%d %H:%M:%S')}] [守護進程] 已由使用者中斷退出")
            break
        except Exception as e:
            print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] [守護進程例外]: {e}")
            time.sleep(5)

if __name__ == "__main__":
    main()
