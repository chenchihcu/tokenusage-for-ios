/**
 * OpenTokenUsage 多配額池 (Multi-Token Pools) 與階層式時間週期型別規範
 */

export interface QuotaTier {
  id: string;                      // 例如 "5h", "weekly"
  label: string;                   // 顯示標籤，例如 "5h limit", "Weekly limit"
  used: number;                    // 已使用百分比 (0~100)
  limit: number;                   // 限制基準 (通常為 100)
  remaining: number;               // 剩餘百分比 (100 - used)
  resetsAt: string | null;         // ISO 8601 重置時間戳
  resetDurationText?: string;      // 友善倒數，例如 "4h 37m", "2d 9h"
  isGoverning?: boolean;           // 是否為該 Pool 內之最嚴格瓶頸週期
}

export interface TokenPool {
  id: string;                      // 唯一標識，例如 "gemini_models", "claude_gpt", "gemini_4_argon"
  name: string;                    // 顯示名稱，例如 "Gemini Models"
  description?: string;            // 描述或所屬模型列表
  effectiveRemaining: number;      // 該 Pool 之有效剩餘百分比 = min(tiers.remaining)
  effectiveUsed: number;           // 該 Pool 之有效用量 = 100 - effectiveRemaining
  primaryResetTime: string | null; // 最緊迫之重置時間
  isCritical: boolean;             // 是否處於危急/耗盡狀態 (effectiveRemaining <= 5)
  tiers: QuotaTier[];              // 該 Pool 所屬的時間週期階層清單
}

export interface ProviderQuotaWithPools {
  provider_id: string;             // "cursor" | "codex" | "antigravity" | "claude" | "grok"
  name: string;                    // "Google Antigravity"
  plan_name: string;               // "Google AI Pro"
  total_quota: number;             // 100
  used_quota: number;              // 平台全域最嚴格用量 (例如 100)
  remaining_percent: number;       // 平台全域最嚴格剩餘 (例如 0)
  reset_time: string;              // 平台全域最嚴格重置時間
  status: string;                  // "active" | "exhausted" | "warning"
  token_pools_json?: string;       // JSON 序列化之 TokenPool[]
  token_pools?: TokenPool[];       // 前端解析後之結構化物件陣列
  metrics_json?: string;           // 既有舊版指標 (相容性保留)
  fetched_at: string;
}
