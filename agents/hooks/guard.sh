#!/bin/bash
# PreToolUse guard for the Bash tool. Runs in every Claude session in this
# repo — interactive, host agent, or container (hooks still fire under
# bypassPermissions). Enforces the never-commit rule, blocks the git
# operations that can erase uncommitted agent work, and blocks the ways an
# agent could reach a shared environment from here: terraform apply, the
# migration runner without an explicit PGHOST (it otherwise fetches Supabase
# creds and migrates the shared dev database), the prod AWS profile, and
# mutating AWS CLI calls.
#
# This is a guardrail, not a jail: a sufficiently creative command can evade
# string matching. Real containment is the container + read-only credentials.
set -uo pipefail

input="$(cat)"
cmd="$(jq -r '.tool_input.command // empty' <<<"$input")"
[[ -z "$cmd" ]] && exit 0

deny() {
  jq -n --arg r "$1" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $r
    }
  }'
  exit 0
}

# --- git ---------------------------------------------------------------------

if grep -Eq '(^|[|;&(`])\s*git[^|;&]*\b(commit|push)\b' <<<"$cmd"; then
  deny "Commits and pushes are reserved for the user. Leave work in the tree; run 'git add -N .' so new files show in git diff."
fi

if grep -Eq '(^|[|;&(`])\s*git[^|;&]*\b(reset[^|;&]*--hard|clean[^|;&]* -[a-zA-Z]*f| (rebase|merge)(\s|$)|branch[^|;&]* -D|checkout[^|;&]* \.|restore[^|;&]* \.|stash[^|;&]*\b(drop|clear))' <<<"$cmd"; then
  deny "Destructive git operation blocked — it can erase uncommitted work. Explain what you need and let the user run it."
fi

# --- rm ----------------------------------------------------------------------

if grep -Eq '(^|[|;&]\s*)rm\s+(-[a-zA-Z]*\s+)*-[a-zA-Z]*r[a-zA-Z]*f' <<<"$cmd" \
   && ! grep -Eq 'rm\s+(-[a-zA-Z]+\s+)+(\S*/)?(build|\.dart_tool|\.venv|\.terraform|/tmp|/private/tmp)(/|\s|$)' <<<"$cmd"; then
  deny "Recursive force-delete outside build/.dart_tool/.venv/.terraform//tmp is blocked for agents."
fi

# --- shared environments -----------------------------------------------------

if grep -Eq '(^|[|;&(`])\s*terraform[^|;&]*\s(apply|destroy|import|taint|untaint|force-unlock|state\s+(mv|rm|push|replace-provider))(\s|$)' <<<"$cmd"; then
  deny "terraform apply/destroy/state changes are the user's. Agents plan and validate only (make test-tf, terraform plan)."
fi

# Only when the script is what runs (command position, after any VAR=... prefixes).
if grep -Eq '(^|[|;&(`])\s*([A-Za-z_]+=\S*\s+)*(bash\s+|sh\s+)?\S*apply_migrations\.sh' <<<"$cmd" \
   && ! grep -Eq '(^|\s)PGHOST=' <<<"$cmd"; then
  deny "apply_migrations.sh without PGHOST fetches Supabase creds and migrates the shared dev database. Run 'make test-db', or prefix with PGHOST=localhost."
fi

if grep -Eq '(AWS_PROFILE=|--profile[ =])heart-prod\b' <<<"$cmd"; then
  deny "The prod AWS account is out of reach for agents."
fi

if grep -Eq '(^|[|;&(`])\s*aws\s+s3\s+(rm|rb|mb)\b' <<<"$cmd" \
   || grep -Eq '(^|[|;&(`])\s*aws\s+s3\s+(cp|sync|mv)\s+\S+\s+s3://' <<<"$cmd" \
   || grep -Eq '(^|[|;&(`])\s*aws\s+[a-z0-9-]+\s+(put|delete|update|create|purge|invoke|send|start|stop|terminate|remove|attach|detach|add|tag|untag|modify|reboot|redrive|change|cancel|assume|associate|disassociate|enable|disable|register|deregister|publish|set)[a-z-]*(\s|$)' <<<"$cmd"; then
  deny "Mutating AWS calls are blocked for agents. Read (get/list/describe/filter) is fine; describe what needs to change and let the user do it."
fi

exit 0
