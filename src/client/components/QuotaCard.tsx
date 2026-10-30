import React from 'react';

export interface QuotaCardProps {
  id: string;
  name: string;
  planName: string;
  remainingPercent: number;
  usedQuota: number;
  totalQuota: number;
  resetTime: string;
  status: string;
  isSelected?: boolean;
  onClick?: () => void;
}

export const QuotaCard: React.FC<QuotaCardProps> = ({
  name,
  planName,
  remainingPercent,
  usedQuota,
  totalQuota,
  resetTime,
  status,
  isSelected,
  onClick,
}) => {
  const isHealthy = remainingPercent >= 30;

  return (
    <div
      onClick={onClick}
      role="button"
      tabIndex={0}
      className={`group relative p-4 rounded-xl transition-all cursor-pointer border text-left ${
        isSelected
          ? 'bg-blue-50/70 border-[#0071e3] shadow-sm'
          : 'bg-white border-[#e5e5ea] hover:border-[#b0b0b8] hover:shadow-sm'
      }`}
    >
      <div className="flex items-center justify-between mb-2">
        <div className="flex items-center gap-2">
          <h3 className="font-semibold text-base text-[#1d1d1f] tracking-tight">{name}</h3>
          <span className="px-2 py-0.5 text-xs font-medium rounded-full bg-[#f5f5f7] text-[#86868b] border border-[#e5e5ea]">
            {planName}
          </span>
        </div>
        <span
          className={`tabular-nums font-bold text-lg ${
            isHealthy ? 'text-[#0071e3]' : 'text-amber-600'
          }`}
        >
          {remainingPercent}%
        </span>
      </div>

      {/* 扁平化進度條 */}
      <div className="w-full h-2 rounded-full bg-[#e5e5ea] overflow-hidden mb-2.5">
        <div
          className={`h-full transition-all duration-500 rounded-full ${
            isHealthy ? 'bg-[#0071e3]' : 'bg-amber-500'
          }`}
          style={{ width: `${Math.min(100, Math.max(0, remainingPercent))}%` }}
        />
      </div>

      <div className="flex items-center justify-between text-xs text-[#86868b]">
        <span className="tabular-nums">
          已用: {usedQuota} / {totalQuota}
        </span>
        <span className="inline-flex items-center gap-1">
          <span className="w-1.5 h-1.5 rounded-full bg-emerald-500" />
          {resetTime}
        </span>
      </div>
    </div>
  );
};
