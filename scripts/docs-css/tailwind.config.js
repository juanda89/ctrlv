/**
 * Tailwind config for the static docs/ landing pages.
 *
 * History: the pages originally styled themselves at runtime via the
 * cdn.tailwindcss.com Play CDN with per-page inline configs. That domain was
 * retired upstream and every page rendered unstyled, so the CSS is now
 * compiled ahead of time into docs/assets/tailwind.css. This config is the
 * superset of those old inline configs — keep it in sync if pages start
 * using new theme tokens.
 *
 * Content paths are relative to this directory; the build script runs the
 * CLI from here (see scripts/build-docs-css.sh).
 */
module.exports = {
  darkMode: "class",
  content: ["../../docs/*.html"],
  theme: {
    extend: {
      colors: {
        primary: "#3B82F6",
        "primary-hover": "#2563EB",
        "background-light": "#F8FAFC",
        "background-dark": "#0A0A1A",
        "surface-light": "#FFFFFF",
        "surface-dark": "#16162C",
        "surface-dark-lighter": "#1E1E38",
        "text-light": "#1E293B",
        "text-dark": "#F1F5F9",
        "muted-light": "#64748B",
        "muted-dark": "#94A3B8",
      },
      fontFamily: {
        display: ["Inter", "sans-serif"],
        serif: ["Playfair Display", "serif"],
      },
      borderRadius: {
        DEFAULT: "0.5rem",
        xl: "1rem",
        "2xl": "1.5rem",
      },
    },
  },
  plugins: [require("@tailwindcss/typography")],
};
