/** @type {import('tailwindcss').Config} */
export default {
  content: [
    "./index.html",
    "./src/**/*.{js,ts,jsx,tsx}",
  ],
  theme: {
    extend: {
      fontFamily: {
        sans: ['-apple-system', 'BlinkMacSystemFont', '"SF Pro Display"', '"SF Pro Text"', '"PingFang TC"', '"Noto Sans TC"', 'sans-serif'],
        mono: ['"SF Mono"', 'Menlo', 'Monaco', 'Consolas', '"Courier New"', 'monospace'],
      },
      colors: {
        apple: {
          blue: '#0071e3',
          gray: '#f5f5f7',
          border: '#e5e5ea',
          darkText: '#1d1d1f',
          subText: '#86868b',
        }
      }
    },
  },
  plugins: [],
}
