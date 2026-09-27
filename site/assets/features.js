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

function badges(feature) {
    const labels = [];
    if (TIERS[feature.tier]) labels.push(TIERS[feature.tier]);
    const platforms = new Set(feature.platforms);
    if (platforms.size === 1) labels.push(`${PLATFORMS[[...platforms][0]] ?? [...platforms][0]} only`);
    return labels;
}

// Only the card in its category carries the id: a highlight appears twice.
function card(feature, anchored) {
    const article = el("article", "flex flex-col gap-2 rounded-xl border bg-surface p-5 scroll-mt-6");
    if (anchored) article.id = feature.id;
    article.append(
        el("h3", "font-title text-lg font-semibold text-ink", feature.title),
        el("p", "text-sm text-muted leading-relaxed", feature.pitch),
    );
    const labels = badges(feature);
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

function render(list, root) {
    const shipped = list.features.filter((feature) => feature.since !== null);
    const highlights = shipped.filter((feature) => feature.highlight);
    const sections = [];
    if (highlights.length) {
        sections.push(section("The short version", highlights.map((feature) => card(feature, false))));
    }
    for (const category of list.categories) {
        const features = shipped.filter((feature) => feature.category === category.id);
        if (features.length) {
            sections.push(section(category.title, features.map((feature) => card(feature, true)), category.id));
        }
    }
    root.append(...sections);
    return sections.length > 0;
}

document.addEventListener("DOMContentLoaded", async () => {
    const root = document.getElementById("features");
    let shown = false;
    try {
        const response = await fetch("data/features.json");
        const list = response.ok ? await response.json() : null;
        if (Array.isArray(list?.categories) && Array.isArray(list?.features)) {
            shown = render(list, root);
        }
    } catch (_) {
        // A non-JSON answer (the index.html fallback) or a network error.
    }
    root.hidden = !shown;
    document.getElementById("features-empty").hidden = shown;
    // Deep links to a feature land before the cards exist; scroll once they do.
    if (shown && location.hash) {
        document.getElementById(decodeURIComponent(location.hash.slice(1)))?.scrollIntoView();
    }
});

