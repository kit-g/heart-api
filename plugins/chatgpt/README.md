# Heart's ChatGPT plugin

The package OpenAI's plugin directory takes: Heart's MCP server (`mcp.heart-of.me`) with the
listing's name, copy and logo. Nothing runs from here; the server is `api/`. Submission steps and
what the form asks for: `docs/2026-10-04.mcp.md`, *Directories*.

- `plugin.json`: the listing. `displayName` and `shortDescription` are capped at 30 characters on
  final submission, `defaultPrompt` at three prompts of 128.
- `mcp.json`: the one server. Auth isn't declared: the server answers `401` with its protected
  resource metadata, and ChatGPT registers itself by CIMD (`2026-10-04.oauth.md`).
- `assets/logo.png`: the mark on a paper tile, so it holds up on a dark background.

Screenshots go in once the tool scan reports the widgets: one per default prompt, 706 px wide and
400–860 px tall, without ChatGPT's own prompt in them.

Reviewer credentials never go in the package; they are entered in the dashboard.

Build the upload from the repository root:

```sh
mkdir -p build
cd plugins/chatgpt && zip -r ../../build/heart-chatgpt.zip plugin.json mcp.json assets
```

Inspect the resulting archive before uploading; keep reviewer credentials and unrelated files out of it.

Bump `version` with each upload that changes the package.

The function URL renames the `401`'s `WWW-Authenticate` to `x-amzn-remapped-www-authenticate`. ChatGPT
signs in regardless, through `/.well-known/oauth-protected-resource` at the host's root; hosts that read
only the header don't find sign-in.

The eight review cases describe expected behaviour, not test results. Run them against the saved
submission version with the dedicated reviewer account. In particular, `list_templates` confirms
exercise names and set counts; the saved `create_template` response supplies individual set reps.
The dashboard takes the rest: domain verification, the tool scan, reviewer credentials and policy
attestations. A server deploy needs no new package: OpenAI rescans the server daily.
