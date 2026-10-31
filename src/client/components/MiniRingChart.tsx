import React from 'react';

export interface MiniRingChartProps {
  value: number; // 剩餘百分比 (0 - 100)
  size?: number; // 像素外徑 (預設 68)
  strokeWidth?: number; // 圓環厚度 (預設 6)
  gradientId: string;
  gradientColors: [string, string];
  isCritical?: boolean;
  label?: string;
  showCenterText?: boolean;
}

export const MiniRingChart: React.FC<MiniRingChartProps> = ({
  value,
  size = 68,
  strokeWidth = 6,
  gradientId,
  gradientColors,
  isCritical = false,
  label,
  showCenterText = true,
}) => {
  const clampedValue = Math.min(100, Math.max(0, value));
  const radius = (size - strokeWidth) / 2;
  const circumference = 2 * Math.PI * radius;
  // 保留至少 2% 視覺線段，避免 0% 時完全消失找不到指示點
  const visualValue = isCritical && clampedValue === 0 ? 0 : Math.max(1.5, clampedValue);
  const strokeDashoffset = circumference - (visualValue / 100) * circumference;

  return (
    <div
      className="relative flex items-center justify-center shrink-0 select-none"
      style={{ width: size, height: size }}
      role="img"
      aria-label={`${label || '配額'}: 剩餘 ${clampedValue}%`}
    >
      <svg
        width={size}
        height={size}
        viewBox={`0 0 ${size} ${size}`}
        className="rotate-[-90deg] transform"
      >
        <defs>
          <linearGradient id={gradientId} x1="0%" y1="0%" x2="100%" y2="100%">
            <stop offset="0%" stopColor={gradientColors[0]} />
            <stop offset="100%" stopColor={gradientColors[1]} />
          </linearGradient>
          {isCritical && (
            <linearGradient id={`${gradientId}-critical`} x1="0%" y1="0%" x2="100%" y2="100%">
              <stop offset="0%" stopColor="#FB7185" />
              <stop offset="100%" stopColor="#E11D48" />
            </linearGradient>
          )}
        </defs>

        {/* 底環背景 */}
        <circle
          cx={size / 2}
          cy={size / 2}
          r={radius}
          fill="transparent"
          stroke="rgba(255, 255, 255, 0.08)"
          strokeWidth={strokeWidth}
        />

        {/* 動態進度前環 */}
        <circle
          cx={size / 2}
          cy={size / 2}
          r={radius}
          fill="transparent"
          stroke={isCritical ? `url(#${gradientId}-critical)` : `url(#${gradientId})`}
          strokeWidth={strokeWidth}
          strokeLinecap="round"
          strokeDasharray={circumference}
          strokeDashoffset={strokeDashoffset}
          className={`transition-all duration-700 ease-out ${isCritical ? 'animate-pulse' : ''}`}
        />
      </svg>

      {/* 中心指標數值 */}
      {showCenterText && (
        <div className="absolute inset-0 flex flex-col items-center justify-center pointer-events-none">
          <span
            className={`font-mono font-black tabular-nums tracking-tight leading-none ${
              size >= 72 ? 'text-lg' : 'text-sm'
            } ${
              isCritical
                ? 'text-rose-400 animate-pulse'
                : clampedValue < 20
                ? 'text-amber-400'
                : 'text-slate-100'
            }`}
          >
            {clampedValue}%
          </span>
          {label && (
            <span className="text-[9px] uppercase font-mono font-bold text-slate-500 mt-0.5 leading-none">
              {label}
            </span>
          )}
        </div>
      )}
    </div>
  );
};
