/** @type {import('tailwindcss').Config} */
export default {
  content: [
    "./index.html",
    "./src/**/*.{js,ts,jsx,tsx}",
  ],
  darkMode: 'class',
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
      colors: {
        cyber: {
          bg: '#090A10',
          base: '#0D111A',
          card: '#121826',
          surface: 'rgba(18, 24, 38, 0.85)',
          border: 'rgba(255, 255, 255, 0.08)',
          borderGlow: 'rgba(255, 255, 255, 0.16)',
          text: '#F8FAFC',
          muted: '#94A3B8',
        },
        neon: {
          cyan: '#00F2FE',
          blue: '#4FACFE',
          emerald: '#00FF87',
          mint: '#60EFFF',
          purple: '#A855F7',
          prismBlue: '#4285F4',
          prismPink: '#EC4899',
          amber: '#FF8A00',
          coral: '#FF4E50',
          crimson: '#FF007A',
          violet: '#7928CA',
        },
        apple: {
          blue: '#0A84FF',
          gray: '#1C1C1E',
          border: 'rgba(255, 255, 255, 0.12)',
          darkText: '#F5F5F7',
          subText: '#8E8E93',
        }
      },
      boxShadow: {
        'glow-cyan': '0 0 25px rgba(0, 242, 254, 0.35)',
        'glow-emerald': '0 0 25px rgba(0, 255, 135, 0.35)',
        'glow-purple': '0 0 25px rgba(168, 85, 247, 0.35)',
        'glow-amber': '0 0 25px rgba(255, 138, 0, 0.35)',
        'glow-crimson': '0 0 25px rgba(255, 0, 122, 0.35)',
      },
      keyframes: {
        photonSweep: {
          '0%': { transform: 'translateX(-100%)' },
          '100%': { transform: 'translateX(200%)' },
        },
        livePulse: {
          '0%, 100%': { opacity: '1', transform: 'scale(1)' },
          '50%': { opacity: '0.4', transform: 'scale(0.92)' },
        },
        equalizerBounce: {
          '0%, 100%': { transform: 'scaleY(0.2)' },
          '50%': { transform: 'scaleY(1.0)' },
        }
      },
      animation: {
        'photon-sweep': 'photonSweep 3s ease-in-out infinite',
        'live-pulse': 'livePulse 2s cubic-bezier(0.4, 0, 0.6, 1) infinite',
        'equalizer': 'equalizerBounce 1s ease-in-out infinite',
      }
    },
  },
  plugins: [],
}
