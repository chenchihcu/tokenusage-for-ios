import React from 'react';
import { AlertTriangle, CheckCircle2, Link2 } from 'lucide-react';

export interface QuotaCardProps {
  id: string;
  name: string;
  planName: string;
  remainingPercent: number;
  usedQuota: number;
  totalQuota: number;
  resetTime: string;
  status: string;
  token_pools_json?: string;
  metrics_json?: string;
  fetched_at?: string;
  isSelected?: boolean;
  onClick?: () => void;
}

// 5 大平台專屬炫彩樣式字典
const PLATFORM_STYLES: Record<string, {
  borderSelect: string;
  glowSelect: string;
  badgeBg: string;
  badgeText: string;
  badgeBorder: string;
  gradient: string;
  accentText: string;
}> = {
  cursor: {
    borderSelect: 'border-cyan-400',
    glowSelect: 'shadow-[0_0_25px_rgba(0,242,254,0.3)]',
    badgeBg: 'bg-cyan-950/60',
    badgeText: 'text-cyan-300',
    badgeBorder: 'border-cyan-500/40',
    gradient: 'bg-gradient-to-r from-[#00F2FE] to-[#4FACFE]',
    accentText: 'text-cyan-400',
  },
  codex: {
    borderSelect: 'border-emerald-400',
    glowSelect: 'shadow-[0_0_25px_rgba(0,255,135,0.3)]',
    badgeBg: 'bg-emerald-950/60',
    badgeText: 'text-emerald-300',
    badgeBorder: 'border-emerald-500/40',
    gradient: 'bg-gradient-to-r from-[#00FF87] to-[#60EFFF]',
    accentText: 'text-emerald-400',
  },
  antigravity: {
    borderSelect: 'border-purple-400',
    glowSelect: 'shadow-[0_0_25px_rgba(168,85,247,0.3)]',
    badgeBg: 'bg-purple-950/60',
    badgeText: 'text-purple-300',
    badgeBorder: 'border-purple-500/40',
    gradient: 'bg-gradient-to-r from-[#4285F4] via-[#A855F7] to-[#EC4899]',
    accentText: 'text-purple-400',
  },
  claude: {
    borderSelect: 'border-amber-400',
    glowSelect: 'shadow-[0_0_25px_rgba(245,158,11,0.3)]',
    badgeBg: 'bg-amber-950/60',
    badgeText: 'text-amber-300',
    badgeBorder: 'border-amber-500/40',
    gradient: 'bg-gradient-to-r from-amber-400 to-orange-400',
    accentText: 'text-amber-400',
  },
  grok: {
    borderSelect: 'border-pink-500',
    glowSelect: 'shadow-[0_0_25px_rgba(255,0,122,0.35)]',
    badgeBg: 'bg-pink-950/60',
    badgeText: 'text-pink-300',
    badgeBorder: 'border-pink-500/40',
    gradient: 'bg-gradient-to-r from-[#FF007A] to-[#7928CA]',
    accentText: 'text-pink-400',
  },
};

export const QuotaCard: React.FC<QuotaCardProps> = ({
  id,
  name,
  planName,
  remainingPercent,
  usedQuota,
  totalQuota,
  resetTime,
  status,
  token_pools_json,
  metrics_json,
  isSelected,
  onClick,
}) => {
  const pStyle = PLATFORM_STYLES[id] || PLATFORM_STYLES.cursor;
  const isCritical = remainingPercent <= 5;
  const isWarning = remainingPercent < 20 && remainingPercent > 5;
  const isHealthy = remainingPercent >= 20;

  // 格式化重置時間戳 (若為 ISO 8601 轉為本地簡約時間)
  let displayReset = resetTime;
  if (resetTime && resetTime.includes('T')) {
    try {
      const d = new Date(resetTime);
      displayReset = `${d.getMonth() + 1}/${d.getDate()} ${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')} 重置`;
    } catch {
      displayReset = resetTime;
    }
  }

  // 提取多配額池 (Token Pools) 資訊
  let tokenPools: { id: string; name: string; effectiveRemaining: number; isCritical: boolean }[] = [];
  if (token_pools_json) {
    try {
      const parsed = JSON.parse(token_pools_json);
      if (Array.isArray(parsed)) {
        tokenPools = parsed.map((p: any) => ({
          id: p.id,
          name: p.name,
          effectiveRemaining: p.effectiveRemaining,
          isCritical: p.isCritical || p.effectiveRemaining <= 5,
        }));
      }
    } catch {}
  }
  const hasCriticalSubPool = tokenPools.some((p) => p.isCritical);

  // 提取多維度指標 (Session vs Weekly) 雙軌資訊 (作為後備)
  let subMeters: { label: string; used: number; isAlert?: boolean }[] = [];
  if (metrics_json) {
    try {
      const parsed = JSON.parse(metrics_json);
      if (Array.isArray(parsed)) {
        subMeters = parsed
          .filter((m: any) => m.used !== undefined && (m.label === 'Session' || m.label === 'Weekly' || m.label === 'Weekly (Shared)'))
          .map((m: any) => ({
            label: m.label.replace(' (Shared)', ''),
            used: m.used,
            isAlert: m.isAlert || m.used >= 90,
          }));
      }
    } catch {}
  }

  return (
    <div
      onClick={onClick}
      role="button"
      tabIndex={0}
      className={`group relative p-4 rounded-2xl transition-all cursor-pointer border text-left backdrop-blur-xl ${
        isSelected
          ? `bg-slate-900/90 ${pStyle.borderSelect} ${pStyle.glowSelect} ring-1 ring-white/10`
          : 'bg-slate-900/60 border-slate-800/80 hover:bg-slate-900/80 hover:border-slate-700/80'
      }`}
    >
      {/* 頂部細長裝飾流光條 */}
      <div className={`absolute top-0 left-4 right-4 h-[2px] rounded-full opacity-60 group-hover:opacity-100 transition-opacity ${pStyle.gradient}`} />

      <div className="flex items-center justify-between mb-2.5">
        <div className="flex items-center gap-2">
          <h3 className="font-bold text-base text-slate-100 tracking-tight group-hover:text-white transition-colors">
            {name}
          </h3>
          <span className={`px-2 py-0.5 text-[11px] font-semibold rounded-full border ${pStyle.badgeBg} ${pStyle.badgeText} ${pStyle.badgeBorder}`}>
            {planName}
          </span>
          {id === 'grok' && (
            <span className="flex items-center gap-0.5 px-1.5 py-0.5 rounded-full bg-slate-800 border border-slate-700 text-[10px] text-slate-400" title="週期連動綁定 Cursor">
              <Link2 className="w-2.5 h-2.5 text-cyan-400" />
              Bonded
            </span>
          )}
        </div>

        {/* 剩餘百分比 */}
        <div className="flex items-baseline gap-1">
          <span
            className={`tabular-nums font-mono font-black text-2xl tracking-tight ${
              isCritical
                ? 'text-rose-400 animate-pulse'
                : isWarning
                ? 'text-amber-400'
                : pStyle.accentText
            }`}
          >
            {remainingPercent}%
          </span>
          <span className="text-[10px] font-medium text-slate-500 uppercase">剩餘</span>
        </div>
      </div>

      {/* 炫彩動態進度條 */}
      <div className="w-full h-2 rounded-full bg-slate-950/90 overflow-hidden mb-2.5 border border-slate-800/60">
        <div
          className={`h-full transition-all duration-700 rounded-full ${
            isCritical
              ? 'bg-rose-500 animate-pulse'
              : pStyle.gradient
          }`}
          style={{ width: `${Math.min(100, Math.max(2, remainingPercent))}%` }}
        />
      </div>

      {/* 多配額池迷你膠囊標籤 (Mini-Chips) 或雙軌指標 */}
      {tokenPools.length > 0 ? (
        <div className="flex flex-wrap items-center gap-1.5 mb-2.5 text-[10px] font-mono">
          {tokenPools.map((tp) => (
            <span
              key={tp.id}
              className={`flex items-center gap-1 px-1.5 py-0.5 rounded-md border ${
                tp.isCritical
                  ? 'bg-rose-950/70 text-rose-300 border-rose-500/50 shadow-[0_0_8px_rgba(244,63,94,0.25)] animate-pulse'
                  : 'bg-slate-800/80 text-slate-300 border-slate-700/60'
              }`}
            >
              <span className="text-slate-400 font-medium truncate max-w-[90px]">{tp.name}:</span>
              <span className={`font-bold ${tp.isCritical ? 'text-rose-400' : 'text-slate-100'}`}>
                {tp.effectiveRemaining}%
              </span>
              {tp.isCritical && <span>⚠️</span>}
            </span>
          ))}
        </div>
      ) : (
        subMeters.length >= 2 && (
          <div className="flex items-center gap-1.5 mb-2.5 text-[10px] font-mono">
            {subMeters.map((sm, idx) => (
              <span
                key={idx}
                className={`flex items-center gap-1 px-1.5 py-0.5 rounded-md border ${
                  sm.isAlert
                    ? 'bg-rose-950/60 text-rose-300 border-rose-500/40 shadow-[0_0_8px_rgba(244,63,94,0.2)]'
                    : 'bg-slate-800/80 text-slate-300 border-slate-700/60'
                }`}
              >
                <span className="text-slate-400">{sm.label}:</span>
                <span className={`font-bold ${sm.isAlert ? 'text-rose-400' : 'text-slate-200'}`}>
                  {sm.used}%
                </span>
                {sm.isAlert && <span className="text-rose-400">⚠️</span>}
              </span>
            ))}
          </div>
        )
      )}

      {/* 底部輔助指標 */}
      <div className="flex items-center justify-between text-xs text-slate-400">
        <div className="flex items-center gap-1.5">
          {isCritical ? (
            <span className="inline-flex items-center gap-1 text-[11px] font-semibold text-rose-400 bg-rose-950/60 px-1.5 py-0.5 rounded border border-rose-500/30">
              <AlertTriangle className="w-3 h-3 text-rose-400" /> 配額耗盡 / 告警
            </span>
          ) : hasCriticalSubPool ? (
            <span className="inline-flex items-center gap-1 text-[11px] font-semibold text-amber-400 bg-amber-950/60 px-1.5 py-0.5 rounded border border-amber-500/30">
              <AlertTriangle className="w-3 h-3 text-amber-400" /> 部分配額池耗盡
            </span>
          ) : (
            <span className="tabular-nums text-slate-400">
              用量: <span className="text-slate-200 font-mono">{usedQuota}%</span>
            </span>
          )}
        </div>

        <div className="flex items-center gap-1.5 text-[11px]">
          <span className={`w-1.5 h-1.5 rounded-full ${isHealthy ? 'bg-emerald-400' : 'bg-amber-400'} animate-pulse`} />
          <span className="text-slate-400 font-mono">{displayReset}</span>
        </div>
      </div>
    </div>
  );
};
