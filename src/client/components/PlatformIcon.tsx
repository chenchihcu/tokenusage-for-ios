import React from 'react';

interface PlatformIconProps {
  id: string;
  className?: string;
}

/**
 * 5 大 AI 平台專屬 SVG Path 圖示 (Vector Path Icons)
 * 針對 iPhone Duo 高密度介面與深色黑曜石美學設計
 */
export const PlatformIcon: React.FC<PlatformIconProps> = ({ id, className = 'w-4 h-4' }) => {
  switch (id) {
    case 'cursor':
      return (
        <svg viewBox="0 0 24 24" fill="none" className={className} aria-hidden="true">
          <path
            d="M4 3.5L20 11.2L12.6 13.4L10.4 20.8L4 3.5Z"
            stroke="currentColor"
            strokeWidth="1.9"
            strokeLinejoin="round"
          />
          <path d="M12.6 13.4L17.5 18.3" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" />
        </svg>
      );
    case 'codex':
      return (
        <svg viewBox="0 0 24 24" fill="none" className={className} aria-hidden="true">
          <path
            d="M8.5 7L3.5 12L8.5 17"
            stroke="currentColor"
            strokeWidth="1.9"
            strokeLinecap="round"
            strokeLinejoin="round"
          />
          <path
            d="M15.5 7L20.5 12L15.5 17"
            stroke="currentColor"
            strokeWidth="1.9"
            strokeLinecap="round"
            strokeLinejoin="round"
          />
          <path d="M13.5 5.5L10.5 18.5" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" />
        </svg>
      );
    case 'antigravity':
      return (
        <svg viewBox="0 0 24 24" fill="none" className={className} aria-hidden="true">
          <path
            d="M12 3C12 8.2 15.8 12 21 12C15.8 12 12 15.8 12 21C12 15.8 8.2 12 3 12C8.2 12 12 8.2 12 3Z"
            stroke="currentColor"
            strokeWidth="1.8"
            strokeLinejoin="round"
          />
          <circle cx="12" cy="12" r="2.1" fill="currentColor" />
        </svg>
      );
    case 'claude':
      return (
        <svg viewBox="0 0 24 24" fill="none" className={className} aria-hidden="true">
          <path
            d="M12 3V21M4.2 7.5L19.8 16.5M19.8 7.5L4.2 16.5"
            stroke="currentColor"
            strokeWidth="1.85"
            strokeLinecap="round"
          />
          <circle cx="12" cy="12" r="2.2" fill="currentColor" />
        </svg>
      );
    case 'grok':
      return (
        <svg viewBox="0 0 24 24" fill="none" className={className} aria-hidden="true">
          <path
            d="M5 5L19 19M19 5L13.5 10.5M10.5 13.5L5 19"
            stroke="currentColor"
            strokeWidth="1.95"
            strokeLinecap="round"
          />
          <path
            d="M15.5 4.5C18.5 6 20 9 20 12.2C20 16.5 16.5 20 12.2 20"
            stroke="currentColor"
            strokeWidth="1.5"
            strokeLinecap="round"
            strokeDasharray="2.5 2.5"
          />
        </svg>
      );
    default:
      return (
        <svg viewBox="0 0 24 24" fill="none" className={className} aria-hidden="true">
          <circle cx="12" cy="12" r="8" stroke="currentColor" strokeWidth="1.8" />
        </svg>
      );
  }
};
