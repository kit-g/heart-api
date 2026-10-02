// Renders features.html from data/features.json, which heart-of-yours uploads
// on release. The file follows the app's contract (its release-notes skill and
// test/features_content_test.dart):
//   - `categories` is ordered, and that order is the page's order
//   - `"since": null` is merged but unreleased, and is left out
//   - `highlight` marks the handful the page leads with
//   - `title` and `pitch` are plain text, set as text, never parsed
//   - `id` is stable forever, so it is the anchor other pages link to
//
// Until the app has uploaded one, the distribution answers a missing key with
// index.html and a 200, so anything that is not a feature list shows the empty
// state rather than an error.

const TIERS = {premium: "Premium", coach: "Coach"};
const PLATFORMS = {ios: "iOS", android: "Android"};

function el(tag, className, text) {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text !== undefined) node.textContent = text;
    return node;
}

// iPadOS asks for desktop sites by default, so its user agent says Macintosh;
// a touch screen is what tells it apart from a Mac.
function guessPlatform() {
    const agent = navigator.userAgent;
    if (/iPhone|iPad/.test(agent) || (/Macintosh/.test(agent) && navigator.maxTouchPoints > 1)) return "ios";
    if (/Android/.test(agent)) return "android";
    return "all";
}

// ?platform= is a choice someone made, so it beats the guess; anything
// unrecognised is ignored rather than filtering everything out.
function initialPlatform() {
    const asked = new URLSearchParams(location.search).get("platform");
    return asked === "all" || Object.hasOwn(PLATFORMS, asked) ? asked : guessPlatform();
}

function shows(feature, platform) {
    return platform === "all" || feature.platforms.includes(platform);
}

// "iOS only" says nothing once the page already shows only iOS.
function badges(feature, platform) {
    const labels = [];
    if (TIERS[feature.tier]) labels.push(TIERS[feature.tier]);
    const platforms = new Set(feature.platforms);
    if (platform === "all" && platforms.size === 1) {
        labels.push(`${PLATFORMS[[...platforms][0]] ?? [...platforms][0]} only`);
    }
    return labels;
}

// Only the card in its category carries the id: a highlight appears twice.
function card(feature, anchored, platform) {
    const article = el("article", "flex flex-col gap-2 rounded-xl border bg-surface p-5 scroll-mt-6");
    if (anchored) article.id = feature.id;
    article.append(
        el("h3", "font-title text-lg font-semibold text-ink", feature.title),
        el("p", "text-sm text-muted leading-relaxed", feature.pitch),
    );
    const labels = badges(feature, platform);
    if (labels.length) {
        const row = el("div", "flex flex-wrap gap-3");
        for (const label of labels) {
            row.append(el("span", "text-xs font-semibold text-accent-ink uppercase tracking-wider", label));
        }
        article.append(row);
    }
    return article;
}

function section(title, cards, id) {
    const node = el("section", "flex flex-col gap-6 scroll-mt-6");
    if (id) node.id = id;
    const grid = el("div", "grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-5");
    grid.append(...cards);
    node.append(el("h2", "font-title text-2xl sm:text-3xl font-semibold tracking-tight text-ink", title), grid);
    return node;
}

// Replaces whatever is rendered and returns how many features are on the page,
// each counted once: highlights are repeats of category cards.
function render(list, root, platform) {
    const shipped = list.features.filter((feature) => feature.since !== null && shows(feature, platform));
    const highlights = shipped.filter((feature) => feature.highlight);
    const sections = [];
    if (highlights.length) {
        sections.push(section("The short version", highlights.map((feature) => card(feature, false, platform))));
    }
    let count = 0;
    for (const category of list.categories) {
        const features = shipped.filter((feature) => feature.category === category.id);
        if (features.length) {
            sections.push(section(category.title, features.map((feature) => card(feature, true, platform)), category.id));
            count += features.length;
        }
    }
    if (count) {
        root.replaceChildren(...sections);
    } else {
        root.replaceChildren(el("p", "text-muted leading-relaxed", "Nothing on this platform yet."));
    }
    return count;
}

document.addEventListener("DOMContentLoaded", async () => {
    const root = document.getElementById("features");
    const filter = document.getElementById("platform-filter");
    const status = document.getElementById("features-count");
    const buttons = [...filter.querySelectorAll("button[data-platform]")];
    let list = null;
    try {
        const response = await fetch("data/features.json");
        const body = response.ok ? await response.json() : null;
        if (Array.isArray(body?.categories) && Array.isArray(body?.features)) list = body;
    } catch (_) {
        // A non-JSON answer (the index.html fallback) or a network error.
    }

    const show = (platform) => {
        for (const button of buttons) {
            button.setAttribute("aria-pressed", String(button.dataset.platform === platform));
        }
        return render(list, root, platform);
    };

    // An empty list under All is "nothing yet"; empty under one platform is
    // just that platform, and the control stays so the visitor can switch back.
    const shown = list !== null && show("all") > 0;
    root.hidden = !shown;
    filter.hidden = !shown;
    document.getElementById("features-empty").hidden = shown;
    if (!shown) return;

    let platform = initialPlatform();
    if (platform !== "all") show(platform);

    // Deep links to a feature land before the cards exist, and may name one
    // the platform hides: fall back to All rather than land nowhere.
    const reveal = () => {
        if (!location.hash) return;
        const id = decodeURIComponent(location.hash.slice(1));
        if (!document.getElementById(id) && platform !== "all") {
            show("all");
            if (document.getElementById(id)) platform = "all";
            else show(platform);
        }
        document.getElementById(id)?.scrollIntoView();
    };
    reveal();
    window.addEventListener("hashchange", reveal);

    // replaceState keeps the hash and spares the back button a step per click.
    for (const button of buttons) {
        button.addEventListener("click", () => {
            platform = button.dataset.platform;
            const count = show(platform);
            const url = new URL(location.href);
            url.searchParams.set("platform", platform);
            history.replaceState(history.state, "", url);
            status.textContent = `${count} ${count === 1 ? "feature" : "features"}`;
        });
    }
});
