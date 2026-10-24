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

    // On a phone, a store badge marked data-store shows only for its own
    // platform. iPadOS reports itself as a Mac, so a touch Mac counts as iOS.
    const ua = navigator.userAgent;
    const platform = /iPhone|iPad|iPod/.test(ua) || (/Macintosh/.test(ua) && navigator.maxTouchPoints > 1)
        ? "ios"
        : /Android/.test(ua) ? "android" : null;
    if (platform) {
        document.querySelectorAll("[data-store]").forEach((badge) => {
            badge.hidden = badge.dataset.store !== platform;
        });
    }
});
