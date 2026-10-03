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
