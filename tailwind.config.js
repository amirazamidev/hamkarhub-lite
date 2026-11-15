/** @type {import('tailwindcss').Config} */
// Tailwind CSS v3 (خالص جاوااسکریپت) — بدون موتور نیتیو oxide
// تا روی پردازنده‌های قدیمی (AMD Phenom / بدون SSE4.2) هم بدون خطا اجرا شود.
export default {
  content: ['./index.html', './src/**/*.{js,ts,jsx,tsx}'],
  theme: {
    extend: {
      fontFamily: {
        sans: [
          'Vazirmatn',
          'system-ui',
          '-apple-system',
          'BlinkMacSystemFont',
          'Segoe UI',
          'Roboto',
          'sans-serif',
        ],
        mono: [
          'ui-monospace',
          'SFMono-Regular',
          'Menlo',
          'Monaco',
          'Consolas',
          'Liberation Mono',
          'Courier New',
          'monospace',
        ],
      },
      // هم‌راستا کردن پیش‌فرض‌های v3 با رفتار Tailwind v4 که اپ بر پایه آن طراحی شده است
      borderColor: {
        DEFAULT: 'currentColor',
      },
      divideColor: {
        DEFAULT: 'currentColor',
      },
    },
  },
  plugins: [],
};
