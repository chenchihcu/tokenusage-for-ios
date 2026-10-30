export interface LedgerEntry {
  id: string;
  provider: string;
  modelId: string;
  promptTokens: number;
  completionTokens: number;
  thinkingTokens: number;
  totalTokens: number;
  costUsd: number;
  sessionId?: string;
  createdAt?: string;
}

export interface QuotaGuardPolicy {
  dailySpendLimitUsd: number;
  monthlySpendLimitUsd: number;
  hardStopEnabled: boolean;
}

export class UsageLedgerService {
  private inMemoryLedger: LedgerEntry[] = [];
  private policy: QuotaGuardPolicy = {
    dailySpendLimitUsd: 10.0,
    monthlySpendLimitUsd: 50.0,
    hardStopEnabled: true,
  };

  /**
   * 記錄 Token 與花費，並檢查 Quota Hard Stop
   */
  async recordUsage(entry: Omit<LedgerEntry, 'id' | 'createdAt'>): Promise<LedgerEntry> {
    const totalTokens = entry.promptTokens + entry.completionTokens + (entry.thinkingTokens || 0);
    const newEntry: LedgerEntry = {
      ...entry,
      id: `led_${Date.now()}_${Math.random().toString(36).substring(2, 7)}`,
      totalTokens,
      createdAt: new Date().toISOString(),
    };

    // 檢查每日累計硬阻斷配額
    const currentDailySpend = this.getTodayTotalSpend();
    if (this.policy.hardStopEnabled && currentDailySpend + newEntry.costUsd > this.policy.dailySpendLimitUsd) {
      throw new Error(
        `[Quota Hard Stop] 今日 AI 總花費 ($${(currentDailySpend + newEntry.costUsd).toFixed(2)}) 已達上限 ($${this.policy.dailySpendLimitUsd})，已自動阻斷非必要調用`
      );
    }

    this.inMemoryLedger.push(newEntry);
    return newEntry;
  }

  getTodayTotalSpend(): number {
    const todayStr = new Date().toISOString().slice(0, 10);
    return this.inMemoryLedger
      .filter((e) => (e.createdAt || '').startsWith(todayStr))
      .reduce((acc, cur) => acc + cur.costUsd, 0);
  }

  getRecentEntries(limit = 10): LedgerEntry[] {
    return [...this.inMemoryLedger].reverse().slice(0, limit);
  }

  setPolicy(newPolicy: Partial<QuotaGuardPolicy>) {
    this.policy = { ...this.policy, ...newPolicy };
  }

  getPolicy(): QuotaGuardPolicy {
    return { ...this.policy };
  }
}

export const defaultLedger = new UsageLedgerService();
