import React from 'react';
import { QuotaCardProps } from './QuotaCard';
import { MiniRingChart } from './MiniRingChart';
import { TokenPool } from '../../types/quota';
import { HandednessMode } from './ViewModeSelector';
import { PlatformIcon } from './PlatformIcon';
import { extractResetWindowSummary } from '../utils/resetMonitor';
import {
  Activity,
  AlertTriangle,
  Clock,
  ArrowUpRight,
  Filter,
} from 'lucide-react';

interface CockpitOverviewProps {
  quotas: QuotaCardProps[];
  selectedId: string;
  onSelectPlatform: (id: string) => void;
  onOpenDetail: (id: string) => void;
  isOnline: boolean;
  linkLabel?: string;
  countdownSeconds: number;
  filterAlertOnly?: boolean;
  onToggleFilterAlert?: () => void;
  handedness?: HandednessMode;
  compact?: boolean;
}

// 5 大平台主題配色與漸變
const PLATFORM_THEMES: Record<
  string,
  {
    gradient: [string, string];
    border: string;
    borderSelected: string;
    glowSelected: string;
    textAccent: string;
    badgeBg: string;
    badgeText: string;
    badgeBorder: string;
  }
> = {
  cursor: {
    gradient: ['#00F2FE', '#4FACFE'],
    border: 'border-cyan-500/20',
    borderSelected: 'border-cyan-400',
    glowSelected: 'shadow-[0_0_20px_rgba(0,242,254,0.25)]',
    textAccent: 'text-cyan-400',
    badgeBg: 'bg-cyan-950/60',
    badgeText: 'text-cyan-300',
    badgeBorder: 'border-cyan-500/40',
  },
  codex: {
    gradient: ['#00FF87', '#60EFFF'],
    border: 'border-emerald-500/20',
    borderSelected: 'border-emerald-400',
    glowSelected: 'shadow-[0_0_20px_rgba(0,255,135,0.25)]',
    textAccent: 'text-emerald-400',
    badgeBg: 'bg-emerald-950/60',
    badgeText: 'text-emerald-300',
    badgeBorder: 'border-emerald-500/40',
  },
  antigravity: {
    gradient: ['#4285F4', '#A855F7'],
    border: 'border-purple-500/20',
    borderSelected: 'border-purple-400',
    glowSelected: 'shadow-[0_0_20px_rgba(168,85,247,0.25)]',
    textAccent: 'text-purple-400',
    badgeBg: 'bg-purple-950/60',
    badgeText: 'text-purple-300',
    badgeBorder: 'border-purple-500/40',
  },
  claude: {
    gradient: ['#F59E0B', '#FB923C'],
    border: 'border-amber-500/20',
    borderSelected: 'border-amber-400',
    glowSelected: 'shadow-[0_0_20px_rgba(245,158,11,0.25)]',
    textAccent: 'text-amber-400',
    badgeBg: 'bg-amber-950/60',
    badgeText: 'text-amber-300',
    badgeBorder: 'border-amber-500/40',
  },
};

export const CockpitOverview: React.FC<CockpitOverviewProps> = ({
  quotas,
  selectedId,
  onSelectPlatform,
  onOpenDetail,
  isOnline,
  linkLabel,
  countdownSeconds,
  filterAlertOnly = false,
  onToggleFilterAlert,
  compact = false,
}) => {
  // 找出全平台最嚴格治理瓶頸 (Governing Bottleneck)
  let governingPlatform: QuotaCardProps | null = null;
  let governingPoolName = '';
  let governingRemaining = 100;

  quotas.forEach((q) => {
    if (q.remainingPercent < governingRemaining) {
      governingRemaining = q.remainingPercent;
      governingPlatform = q;
    }

    if (q.token_pools_json) {
      try {
        const pools: TokenPool[] = JSON.parse(q.token_pools_json);
        pools.forEach((p) => {
          if (p.effectiveRemaining < governingRemaining) {
            governingRemaining = p.effectiveRemaining;
            governingPlatform = q;
            governingPoolName = p.name;
          }
        });
      } catch {}
    }
  });

  const criticalCount = quotas.filter((q) => q.remainingPercent <= 5).length;
  const warningCount = quotas.filter((q) => q.remainingPercent > 5 && q.remainingPercent < 20).length;

  // 風險優先動態過濾與分組 (Risk-First Filter & Grouping)
  const filteredQuotas = filterAlertOnly
    ? quotas.filter(
        (q) =>
          q.remainingPercent <= 20 ||
          (governingPlatform && q.id === (governingPlatform as QuotaCardProps).id)
      )
    : quotas;

  return (
    <div className="flex flex-col h-full w-full bg-slate-950 overflow-y-auto select-none p-2 sm:p-3 lg:p-4 gap-2 sm:gap-3 fab-clearance">
      {/* 1. 即時脈動監控中樞 (System Pulse Monitor - Apple HIG Touch Safe) */}
      <section
        aria-label="系統脈動監控"
        className="shrink-0 rounded-xl bg-slate-900/80 border border-slate-800/80 p-2.5 sm:p-3 flex flex-wrap items-center justify-between gap-2 backdrop-blur-xl"
      >
        {/* 左側：最嚴格治理瓶頸提示 (Governing Bottleneck Monitor) */}
        <div className="flex items-center gap-2 min-w-0">
          <div
            className={`w-8 h-8 rounded-lg flex items-center justify-center shrink-0 ${
              criticalCount > 0
                ? 'bg-rose-500/20 text-rose-400 border border-rose-500/40 animate-pulse'
                : warningCount > 0
                ? 'bg-amber-500/20 text-amber-400 border border-amber-500/40'
                : 'bg-emerald-500/20 text-emerald-400 border border-emerald-500/40'
            }`}
          >
            {criticalCount > 0 ? (
              <AlertTriangle className="w-4 h-4" />
            ) : (
              <Activity className="w-4 h-4" />
            )}
          </div>

          <div className="flex flex-col min-w-0">
            <div className="flex items-center gap-2">
              <span className="text-[10px] font-mono font-bold tracking-wider text-slate-400 uppercase">
                GOVERNING BOTTLENECK 瓶頸中樞
              </span>
              <span
                className={`text-[10px] font-mono font-bold px-1.5 py-0.2 rounded ${
                  criticalCount > 0
                    ? 'bg-rose-950 text-rose-300 border border-rose-600/50'
                    : 'bg-slate-800 text-slate-300'
                }`}
              >
                {criticalCount > 0 ? `${criticalCount} EXHAUSTED` : 'NORMAL 水位充足'}
              </span>
            </div>
            <div className="flex items-baseline gap-1.5 truncate">
              <span className="text-xs sm:text-sm font-bold text-slate-100 truncate">
                {governingPlatform
                  ? `${(governingPlatform as QuotaCardProps).name}${
                      governingPoolName ? ` · ${governingPoolName}` : ''
                    }`
                  : '全平台運作正常'}
              </span>
              <span
                className={`font-mono font-black text-xs sm:text-sm tabular-nums ${
                  governingRemaining <= 5
                    ? 'text-rose-400 animate-pulse'
                    : governingRemaining < 20
                    ? 'text-amber-400'
                    : 'text-emerald-400'
                }`}
              >
                {governingRemaining}% REMAINING
              </span>
            </div>
          </div>
        </div>

        {/* 右側：單手過濾晶片與高密度 KPI 膠囊 (Apple HIG ≥ 44pt Touch Targets) */}
        <div
          className="flex flex-wrap items-center gap-2 text-[11px] font-mono shrink-0"
        >
          {/* 單手快速過濾晶片 (Quick Filter Chip: ALL vs ⚠️ ALERTS) */}
          {onToggleFilterAlert && (
            <button
              type="button"
              onClick={onToggleFilterAlert}
              aria-pressed={filterAlertOnly}
              title="單手快速過濾：切換【全部平台】與【僅告警平台】"
              className={`flex items-center gap-1.5 px-3 py-1.5 rounded-lg font-mono font-bold transition-all min-h-[44px] active:scale-95 touch-manipulation border ${
                filterAlertOnly
                  ? 'bg-amber-950/70 border-amber-500/50 text-amber-300 shadow-[0_0_12px_rgba(245,158,11,0.2)]'
                  : 'bg-slate-900 border-slate-800 text-slate-400 hover:text-slate-200'
              }`}
            >
              <Filter className="w-3.5 h-3.5" />
              <span>{filterAlertOnly ? '只看告警' : `全部 ${quotas.length}`}</span>
            </button>
          )}

          <div className="hidden sm:flex items-center gap-1.5 px-2.5 py-1.5 rounded-lg bg-slate-950/60 border border-slate-800 text-slate-300 min-h-[44px]">
            <span className="text-slate-500 uppercase text-[9px] font-bold">PLATFORMS</span>
            <span className="font-bold text-slate-100 tabular-nums">
              {filteredQuotas.length}/{quotas.length}
            </span>
            <span className="w-1.5 h-1.5 rounded-full bg-emerald-400" />
          </div>

          <div className="flex items-center gap-1.5 px-2.5 py-1.5 rounded-lg bg-slate-950/60 border border-slate-800 text-slate-300 min-h-[44px]">
            <span className="text-slate-500 uppercase text-[9px] font-bold">CADENCE</span>
            <span className="font-bold text-cyan-400 tabular-nums">
              {countdownSeconds > 0 ? `${countdownSeconds}s` : 'MANUAL'}
            </span>
          </div>

          <div
            className={`flex items-center gap-1.5 px-2.5 py-1.5 rounded-lg border min-h-[44px] ${
              isOnline
                ? 'bg-emerald-950/40 border-emerald-500/30 text-emerald-300'
                : 'bg-amber-950/40 border-amber-500/30 text-amber-300'
            }`}
          >
            <span className="w-1.5 h-1.5 rounded-full bg-current animate-pulse" />
            <span className="font-bold text-[10px] uppercase">
              {linkLabel ?? (isOnline ? 'ONLINE' : 'CACHED')}
            </span>
          </div>
        </div>
      </section>

      {/* 2. 五大平台全景矩陣 (Includes All - 5 Platform Cards Grid) */}
      <main
        aria-label="四個服務的額度"
        className={`grid shrink-0 gap-2 sm:gap-3 ${
          filteredQuotas.length <= 2
            ? 'grid-cols-1 sm:grid-cols-2 max-w-2xl mx-auto w-full'
            : 'grid-cols-1 sm:grid-cols-2 lg:grid-cols-4'
        }`}
      >
        {filteredQuotas.length === 0 ? (
          <div className="col-span-full flex flex-col items-center justify-center p-8 rounded-xl bg-slate-900/40 border border-slate-800 text-center">
            <span className="text-emerald-400 font-bold text-sm mb-1">🎉 全平台水位健康充足</span>
            <span className="text-xs text-slate-400">目前無任何平台剩餘配額低於 20%</span>
          </div>
        ) : (
          filteredQuotas.map((item) => {
            const theme = PLATFORM_THEMES[item.id] || PLATFORM_THEMES.cursor;
            const isSelected = item.id === selectedId;
            const isCritical = item.remainingPercent <= 5;
            const isWarning = item.remainingPercent < 20 && !isCritical;

            // 格式化重置日
            let shortReset = item.resetTime;
            if (item.resetTime && item.resetTime.includes('T')) {
              try {
                const d = new Date(item.resetTime);
                shortReset = `${d.getMonth() + 1}/${d.getDate()} ${String(d.getHours()).padStart(
                  2,
                  '0'
                )}:${String(d.getMinutes()).padStart(2, '0')}`;
              } catch {}
            }

            // 提取多配額池 (Token Pools)
            let subPools: { id: string; name: string; remaining: number; isCritical: boolean }[] = [];
            if (item.token_pools_json) {
              try {
                const pools: TokenPool[] = JSON.parse(item.token_pools_json);
                subPools = pools.map((p) => ({
                  id: p.id,
                  name: p.name,
                  remaining: p.effectiveRemaining,
                  isCritical: p.isCritical || p.effectiveRemaining <= 5,
                }));
              } catch {}
            }

            return (
              <article
                key={item.id}
                role="button"
                tabIndex={0}
                onClick={() => onSelectPlatform(item.id)}
                onDoubleClick={() => onOpenDetail(item.id)}
                className={`relative rounded-xl p-2.5 sm:p-3 flex flex-col justify-between transition-all cursor-pointer backdrop-blur-md border touch-manipulation ${
                  isSelected
                    ? `bg-slate-900/95 ${theme.borderSelected} ${theme.glowSelected} ring-1 ring-white/10`
                    : `bg-slate-900/60 ${theme.border} hover:bg-slate-900/80 hover:border-slate-700`
                }`}
              >
                {/* 卡片頂部：平台名 + 方案徽章 + 深入箭頭 (Apple HIG 觸控熱區) */}
                <div>
                  <div
                    className="flex items-center justify-between gap-1 mb-2"
                  >
                    <div className="flex items-center gap-1.5 min-w-0">
                      <span className={`p-1 rounded-md border shrink-0 ${theme.badgeBg} ${theme.badgeText} ${theme.badgeBorder}`}>
                        <PlatformIcon id={item.id} className="w-3.5 h-3.5" />
                      </span>
                      <h3 className="font-bold text-sm text-slate-100 tracking-tight truncate">
                        {item.name}
                      </h3>
                      <span
                        className={`text-[9px] font-mono font-bold px-1.5 py-0.5 rounded border shrink-0 ${theme.badgeBg} ${theme.badgeText} ${theme.badgeBorder}`}
                      >
                        {item.planName}
                      </span>
                    </div>

                    <button
                      type="button"
                      onClick={(e) => {
                        e.stopPropagation();
                        onOpenDetail(item.id);
                      }}
                      title="查看詳情"
                      aria-label={`查看 ${item.name} 詳情`}
                      className="p-2 rounded-lg text-slate-400 hover:text-white hover:bg-slate-800 transition-colors min-h-[44px] min-w-[44px] flex items-center justify-center active:scale-95"
                    >
                      <ArrowUpRight className="w-4 h-4" />
                    </button>
                  </div>

                  {/* 核心視覺：SVG 環形圖表 (Chart) + 主要 Key-Value */}
                  <div
                    className="flex items-center justify-between gap-2 py-1"
                  >
                    {/* SVG 環形圖表 */}
                    <MiniRingChart
                      value={item.remainingPercent}
                      size={compact ? 56 : 64}
                      strokeWidth={compact ? 5 : 6}
                      gradientId={`ring-${item.id}`}
                      gradientColors={theme.gradient}
                      isCritical={isCritical}
                      label="REMAIN"
                      compact={compact}
                    />

                    {/* 核心鍵值對 (Key-Value Deck) */}
                    <div
                      className="flex flex-col gap-1 font-mono text-right"
                    >
                      <div>
                        <span className="text-[9px] text-slate-500 uppercase font-bold block leading-none">
                          USED / BASE
                        </span>
                        <span className="text-xs font-bold text-slate-200 tabular-nums">
                          {item.usedQuota}%
                        </span>
                      </div>

                      <div>
                        <span className="text-[9px] text-slate-500 uppercase font-bold block leading-none">
                          RESET TIME
                        </span>
                        {(() => {
                          const win = extractResetWindowSummary(item);
                          return (
                            <>
                              <span className="text-[10px] font-semibold text-slate-300 tabular-nums truncate max-w-[110px] block leading-none mt-0.5">
                                {shortReset}
                              </span>
                              {win.sessionText !== '--' && (
                                <span className="text-[9px] font-mono text-cyan-300 block leading-none mt-0.5">
                                  5h {win.sessionText} · Wk {win.weeklyText}
                                </span>
                              )}
                            </>
                          );
                        })()}
                      </div>
                    </div>
                  </div>
                </div>

                {/* 多配額池迷你光譜 (Sub-Pool Mini Spectrum) */}
                <div className="pt-2 border-t border-slate-800/80 space-y-1.5">
                  {subPools.length > 0 ? (
                    subPools.slice(0, 3).map((pool) => (
                      <div key={pool.id} className="space-y-0.5">
                        <div className="flex items-center justify-between text-[10px] font-mono leading-none">
                          <span className="text-slate-400 truncate max-w-[90px]">{pool.name}</span>
                          <span
                            className={`font-bold tabular-nums ${
                              pool.isCritical
                                ? 'text-rose-400 animate-pulse'
                                : pool.remaining < 20
                                ? 'text-amber-400'
                                : 'text-slate-300'
                            }`}
                          >
                            {pool.remaining}%
                          </span>
                        </div>
                        <div className="w-full h-1 rounded-full bg-slate-950 overflow-hidden border border-slate-800/40">
                          <div
                            className={`h-full rounded-full transition-all duration-500 ${
                              pool.isCritical
                                ? 'bg-rose-500 animate-pulse'
                                : pool.remaining < 20
                                ? 'bg-amber-400'
                                : 'bg-cyan-400'
                            }`}
                            style={{ width: `${Math.min(100, Math.max(2, pool.remaining))}%` }}
                          />
                        </div>
                      </div>
                    ))
                  ) : (
                    <div className="flex items-center justify-between text-[10px] font-mono py-1">
                      <span className="text-slate-500 uppercase text-[9px] font-bold">STATUS</span>
                      <span
                        className={`font-semibold ${
                          isCritical
                            ? 'text-rose-400'
                            : isWarning
                            ? 'text-amber-400'
                            : 'text-emerald-400'
                        }`}
                      >
                        {isCritical ? '⚠️ EXHAUSTED' : isWarning ? 'LOW WATERMARK' : 'HEALTHY'}
                      </span>
                    </div>
                  )}
                </div>
              </article>
            );
          })
        )}
      </main>
    </div>
  );
};
