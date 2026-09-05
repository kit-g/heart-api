// Tailwind play-CDN config. Every color resolves to a CSS variable declared in
// assets/site.css, so the four pages share one palette and dark mode is driven
// by the OS via prefers-color-scheme rather than a class on <html>.
window.tailwind.config = {
    darkMode: "media",
    theme: {
        extend: {
            colors: {
                ground: "var(--ground)",
                surface: "var(--surface)",
                fill: "var(--fill)",
                ink: "var(--ink)",
                muted: "var(--muted)",
                faint: "var(--faint)",
                border: "var(--border)",
                accent: "var(--accent)",
                "on-accent": "var(--on-accent)",
                "accent-ink": "var(--accent-ink)",
                destructive: "var(--destructive)",
                "on-destructive": "var(--on-destructive)",
            },
            borderColor: {
                DEFAULT: "var(--border)",
            },
            fontFamily: {
                text: ["IBM Plex Sans", "system-ui", "sans-serif"],
                title: ["Literata", "Georgia", "serif"],
            },
            // 8px on buttons and controls, 12px on cards and dialogs. No pills.
            borderRadius: {
                DEFAULT: "8px",
                lg: "8px",
                xl: "12px",
                "2xl": "12px",
                "3xl": "12px",
            },
            typography: {
                DEFAULT: {
                    css: {
                        "--tw-prose-body": "var(--ink)",
                        "--tw-prose-headings": "var(--ink)",
                        "--tw-prose-lead": "var(--muted)",
                        "--tw-prose-links": "var(--accent-ink)",
                        "--tw-prose-bold": "var(--ink)",
                        "--tw-prose-counters": "var(--muted)",
                        "--tw-prose-bullets": "var(--faint)",
                        "--tw-prose-hr": "var(--border)",
                        "--tw-prose-quotes": "var(--ink)",
                        "--tw-prose-quote-borders": "var(--border)",
                        "--tw-prose-captions": "var(--muted)",
                        "--tw-prose-code": "var(--ink)",
                        "--tw-prose-th-borders": "var(--border)",
                        "--tw-prose-td-borders": "var(--border)",
                        h1: {fontFamily: "Literata, Georgia, serif", fontWeight: "600"},
                        h2: {fontFamily: "Literata, Georgia, serif", fontWeight: "600"},
                        h3: {fontFamily: "Literata, Georgia, serif", fontWeight: "600"},
                        a: {textDecoration: "underline", textUnderlineOffset: "2px"},
                    },
                },
            },
        },
    },
};

document.addEventListener("DOMContentLoaded", () => {
    const yearSpan = document.getElementById("footer-year");
    if (yearSpan) {
        yearSpan.textContent = new Date().getFullYear().toString();
    }

    const menuButton = document.getElementById("menu-button");
    const mobileNav = document.getElementById("mobile-nav");
    if (menuButton && mobileNav) {
        menuButton.addEventListener("click", () => {
            const hidden = mobileNav.toggleAttribute("hidden");
            menuButton.setAttribute("aria-expanded", String(!hidden));
        });
    }
});
