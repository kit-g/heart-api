# pages

heart-of.me's rendered pages, built to static HTML with [Jaspr](https://jaspr.site) and
`jaspr_content`. Today that is the blog (heart-api#302), plus the MCP Apps cards (below). The rest of the site is
hand-written HTML in `site/`. These pages wear the same header, footer, `site.css` and
Tailwind build.

## Writing a post

Posts belong to one site: `posts/prod/blog/<slug>.html.md` publishes on heart-of.me, and
`posts/dev/blog/<slug>.html.md` on dev.heart-of.me only (a draft, or a piece not meant for
prod). A post for both goes in both. Add the file, then push. The frontmatter needs three keys:

```markdown
---
title: What Heart is
description: One sentence. It's the link preview, the index entry and the feed item.
date: 2026-10-19T19:12Z
---

Markdown from here.
```

- `date` is `YYYY-MM-DD`, optionally with a UTC time, which orders posts from the same day.
- The post is served at `/blog/<slug>.html`. The `.html` before `.md` is deliberate: the
  apex is shared with the web app, site pages end in `.html`, and extensionless paths are
  the app's.
- `image: cover.png` (optional) sets the link-preview image. A relative name resolves
  next to the post, and a `/`-path from the site root. Without it, the site's `og.png`
  is used.
- Images go in `web/blog/`, shared by both sites. `![alt](diagram.png)` in a post then
  finds `web/blog/diagram.png`.
- Fenced ` ```dart ` blocks are highlighted at build time. Other languages render plain.
- The index (`/blog.html`, from `content/blog.html.md`), the RSS feed (`/blog.xml`) and the
  sitemap entries come from the frontmatter, and every link in them points at the site the
  build is for. Nothing else needs touching.

A post with missing or malformed frontmatter fails the build, naming the file.

## Building and previewing

```
make test-pages                                   # build both sites + analyze, as CI does
scripts/tailwind/build.sh                         # once, or after new classes
scripts/pages.sh dev build/site                   # stage site/ + dev's blog (or prod)
python3 -m http.server -d build/site              # http://localhost:8000/blog.html
```

`scripts/site.sh` runs the same staging for the environment it deploys and syncs `build/site`.

## MCP Apps cards

`lib/cards/` holds cards the API's MCP server shows in an assistant (heart-api#303):
`WorkoutCard`, a component with no browser imports so a server can render it too, and
`McpAppsBridge`, which draws a card from the tool result a host posts. `cards/<name>.dart` is
one page's script. `make cards` compiles each with dart2js into
`api/lib/mcp/widgets/cards.g.dart`, and `api/tool/widget_harness.dart` shows the result in
a browser. `docs/2026-10-18.mcp-widgets.md` has the rest.
