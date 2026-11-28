import React from 'react';

interface PlatformIconProps {
  id: string;
  className?: string;
}

/**
 * 5 大 AI 平台專屬品牌色徽章 SVG 圖示 (Brand-Colored Vector Badges)
 * 每個 Agent 使用高對比品牌底色與專屬輪廓，確保在小尺寸下也能一眼辨識。
 */
export const PlatformIcon: React.FC<PlatformIconProps> = ({ id, className = 'w-5 h-5' }) => {
  switch (id) {
    case 'cursor':
      return (
        <svg viewBox="0 0 24 24" fill="none" className={className} aria-hidden="true">
          <rect x="0.75" y="0.75" width="22.5" height="22.5" rx="6" fill="#0F172A" stroke="#38BDF8" strokeOpacity="0.45" strokeWidth="1.2" />
          {/* 3D Cube-Pointer silhouette */}
          <path
            d="M12 4.2L18.8 8.1V15.9L12 19.8L5.2 15.9V8.1L12 4.2Z"
            stroke="#38BDF8"
            strokeWidth="1.6"
            strokeLinejoin="round"
          />
          <path
            d="M8.8 7.5L16.5 11.4L12.4 12.9L10.9 17L8.8 7.5Z"
            fill="#F8FAFC"
          />
        </svg>
      );
    case 'codex':
      return (
        <svg viewBox="0 0 24 24" fill="none" className={className} aria-hidden="true">
          <rect x="0.75" y="0.75" width="22.5" height="22.5" rx="6" fill="#18181B" stroke="#52525B" strokeWidth="1.2" />
          {/* OpenAI-style 6-petal hexagonal knot */}
          <g stroke="#FFFFFF" strokeWidth="1.45" strokeLinecap="round" strokeLinejoin="round">
            <circle cx="12" cy="8.2" r="2.6" />
            <circle cx="15.3" cy="10.1" r="2.6" />
            <circle cx="15.3" cy="13.9" r="2.6" />
            <circle cx="12" cy="15.8" r="2.6" />
            <circle cx="8.7" cy="13.9" r="2.6" />
            <circle cx="8.7" cy="10.1" r="2.6" />
          </g>
        </svg>
      );
    case 'antigravity':
      return (
        <svg viewBox="0 0 24 24" fill="none" className={className} aria-hidden="true">
          <rect x="0.75" y="0.75" width="22.5" height="22.5" rx="6" fill="#F8FAFC" stroke="#CBD5E1" strokeWidth="1.2" />
          {/* Google 4-color orbital prism */}
          <path d="M12 4.5A7.5 7.5 0 0 1 19.5 12H12V4.5Z" fill="#4285F4" />
          <path d="M19.5 12A7.5 7.5 0 0 1 12 19.5V12H19.5Z" fill="#EA4335" />
          <path d="M12 19.5A7.5 7.5 0 0 1 4.5 12H12V19.5Z" fill="#F6C400" />
          <path d="M4.5 12A7.5 7.5 0 0 1 12 4.5V12H4.5Z" fill="#34A853" />
          <path
            d="M12 7.4C12 10 14 12 16.6 12C14 12 12 14 12 16.6C12 14 10 12 7.4 12C10 12 12 10 12 7.4Z"
            fill="#FFFFFF"
          />
        </svg>
      );
    case 'claude':
      return (
        <svg viewBox="0 0 24 24" fill="none" className={className} aria-hidden="true">
          <rect x="0.75" y="0.75" width="22.5" height="22.5" rx="6" fill="#C2410C" />
          {/* Anthropic 8-ray sunburst */}
          <g stroke="#FFFFFF" strokeWidth="1.9" strokeLinecap="round">
            <path d="M12 4.8V8.4M12 15.6V19.2M4.8 12H8.4M15.6 12H19.2" />
            <path d="M6.9 6.9L9.45 9.45M14.55 14.55L17.1 17.1M17.1 6.9L14.55 9.45M9.45 14.55L6.9 17.1" />
          </g>
        </svg>
      );
    case 'grok':
      return (
        <svg viewBox="0 0 24 24" fill="none" className={className} aria-hidden="true">
          <rect x="0.75" y="0.75" width="22.5" height="22.5" rx="6" fill="#09090B" stroke="#3F3F46" strokeWidth="1.2" />
          <path
            d="M6.5 17.5L17.5 6.5M8.5 7.5L15.5 16.5"
            stroke="#FFFFFF"
            strokeWidth="2.2"
            strokeLinecap="round"
          />
        </svg>
      );
    default:
      return (
        <svg viewBox="0 0 24 24" fill="none" className={className} aria-hidden="true">
          <rect x="0.75" y="0.75" width="22.5" height="22.5" rx="6" fill="#334155" />
          <circle cx="12" cy="12" r="5" stroke="#E2E8F0" strokeWidth="1.8" />
        </svg>
      );
  }
};
