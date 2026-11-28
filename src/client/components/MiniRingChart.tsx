import React from 'react';

export interface MiniRingChartProps {
  value: number; // 剩餘百分比 (0 - 100)
  size?: number; // 像素外徑 (預設 64)
  strokeWidth?: number; // 圓環厚度 (預設 6)
  gradientId: string;
  gradientColors: [string, string];
  isCritical?: boolean;
  label?: string;
  showCenterText?: boolean;
  compact?: boolean;
}

export const MiniRingChart: React.FC<MiniRingChartProps> = ({
  value,
  size: userSize,
  strokeWidth: userStrokeWidth,
  gradientId,
  gradientColors,
  isCritical = false,
  label,
  showCenterText = true,
  compact = false,
}) => {
  const size = userSize ?? (compact ? 44 : 64);
  const strokeWidth = userStrokeWidth ?? (compact ? 5 : 6);

  const clampedValue = Math.min(100, Math.max(0, value));
  const isWarning = !isCritical && clampedValue <= 20;
  const radius = (size - strokeWidth) / 2;
  const circumference = 2 * Math.PI * radius;
  const visualValue = isCritical && clampedValue === 0 ? 0 : Math.max(2, clampedValue);
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
        className="-rotate-90 transform"
      >
        <defs>
          <linearGradient id={gradientId} x1="0%" y1="0%" x2="100%" y2="100%">
            <stop offset="0%" stopColor={gradientColors[0]} />
            <stop offset="100%" stopColor={gradientColors[1]} />
          </linearGradient>
        </defs>

        <circle
          cx={size / 2}
          cy={size / 2}
          r={radius}
          fill="transparent"
          stroke="var(--border-hairline)"
          strokeWidth={strokeWidth}
        />

        <circle
          cx={size / 2}
          cy={size / 2}
          r={radius}
          fill="transparent"
          stroke={
            isCritical
              ? 'var(--status-critical)'
              : isWarning
              ? 'var(--status-warning)'
              : `url(#${gradientId})`
          }
          strokeWidth={strokeWidth}
          strokeLinecap="round"
          strokeDasharray={circumference}
          strokeDashoffset={strokeDashoffset}
          className="transition-all duration-500 ease-out"
        />
      </svg>

      {showCenterText && (
        <div className="absolute inset-0 flex flex-col items-center justify-center pointer-events-none">
          <span
            className={`font-mono font-bold tabular-nums tracking-tight leading-none ${
              size >= 72 ? 'text-body' : 'text-xs'
            } ${
              isCritical
                ? 'text-status-critical'
                : isWarning
                ? 'text-status-warning'
                : 'text-ink-primary'
            }`}
          >
            {clampedValue}%
          </span>
        </div>
      )}
    </div>
  );
};
