// Which store this device installs from: "ios", "android", or null. iPadOS
// reports itself as a Mac, so a touch Mac counts as iOS; Android in desktop
// mode (the default on large tablets) claims Linux, and only Client Hints still
// say Android. Set before the page parses, for get.html's redirect.
window.heartPlatform = (() => {
    const ua = navigator.userAgent;
    if (/iPhone|iPad|iPod/.test(ua) || (/Macintosh/.test(ua) && navigator.maxTouchPoints > 1)) {
        return "ios";
    }
    if (/Android/.test(ua) || navigator.userAgentData?.platform === "Android") {
        return "android";
    }
    return null;
})();

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

    // On a phone, a store badge marked data-store shows only for its own platform.
    const platform = window.heartPlatform;
    if (platform) {
        document.querySelectorAll("[data-store]").forEach((badge) => {
            badge.hidden = badge.dataset.store !== platform;
        });
    }
});
