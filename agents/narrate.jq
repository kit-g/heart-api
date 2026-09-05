# Renders a Claude Code event stream as readable narration: assistant text
# verbatim, tool calls as one-liners. Works on both a session .jsonl (what
# `watch` tails out of a container) and `-p --output-format stream-json`
# (what `host-agent` pipes through); the trailing `result` clause only ever
# matches the latter, and only when the run ends in an error.
if .type == "assistant" then
  (.message.content[]? |
    if .type == "text" then .text + "\n"
    elif .type == "tool_use" then
      "  → " + .name + "  " +
      ((.input.description // .input.command // .input.file_path // .input.prompt // "")
        | tostring | gsub("\\n"; " ") | .[0:140]) + "\n"
    else empty end)
elif .type == "result" and .subtype != "success" then
  "\n✗ " + .subtype + "\n"
else empty end
