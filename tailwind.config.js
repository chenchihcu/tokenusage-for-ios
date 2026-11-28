/** @type {import('tailwindcss').Config} */
export default {
  content: [
    "./index.html",
    "./src/**/*.{js,ts,jsx,tsx}",
  ],
  theme: {
    extend: {
      screens: {
        // iPhone held landscape (Duo split): plenty of width, very little height.
        phoneland: { raw: '(orientation: landscape) and (max-height: 500px)' },
      },
      fontFamily: {
        sans: ['-apple-system', 'BlinkMacSystemFont', '"SF Pro Display"', '"SF Pro Text"', '"PingFang TC"', '"Noto Sans TC"', 'sans-serif'],
        mono: ['"SF Mono"', 'Menlo', 'Monaco', 'Consolas', '"Courier New"', 'monospace'],
      },
      fontSize: {
        kpi: ['1.875rem', { lineHeight: '2.25rem', fontWeight: '700' }],
        'kpi-sm': ['1.5rem', { lineHeight: '1.875rem', fontWeight: '700' }],
        'heading-page': ['1.125rem', { lineHeight: '1.5rem', fontWeight: '700' }],
        'heading-section': ['1rem', { lineHeight: '1.375rem', fontWeight: '700' }],
        subhead: ['0.8125rem', { lineHeight: '1.125rem' }],
        body: ['0.875rem', { lineHeight: '1.25rem' }],
        meta: ['0.75rem', { lineHeight: '1rem' }],
      },
      colors: {
        surface: {
          canvas: 'var(--surface-canvas)',
          card: 'var(--surface-card)',
          elevated: 'var(--surface-elevated)',
          muted: 'var(--surface-muted)',
          chrome: 'var(--surface-chrome)',
        },
        border: {
          hairline: 'var(--border-hairline)',
          strong: 'var(--border-strong)',
        },
        ink: {
          primary: 'var(--ink-primary)',
          secondary: 'var(--ink-secondary)',
          muted: 'var(--ink-muted)',
        },
        accent: {
          primary: 'var(--accent-primary)',
          tint: 'var(--accent-tint)',
        },
        status: {
          healthy: 'var(--status-healthy)',
          'healthy-bg': 'var(--status-healthy-bg)',
          warning: 'var(--status-warning)',
          'warning-bg': 'var(--status-warning-bg)',
          critical: 'var(--status-critical)',
          'critical-bg': 'var(--status-critical-bg)',
        },
      },
      boxShadow: {
        'hig-card': '0 1px 2px rgba(0, 0, 0, 0.04), 0 1px 3px rgba(0, 0, 0, 0.03)',
        'hig-dock': '0 8px 24px rgba(0, 0, 0, 0.12), 0 1px 3px rgba(0, 0, 0, 0.08)',
        'hig-drawer': '-8px 0 32px rgba(0, 0, 0, 0.14)',
      },
    },
  },
  plugins: [],
};
