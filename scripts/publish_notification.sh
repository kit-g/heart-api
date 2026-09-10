#!/usr/bin/env bash
# Publish a deploy-run notification to the monitoring SNS topic.
#
# Everything it reports comes from the workflow's own `needs.<job>.result`
# values, passed in as environment variables — no artifacts, no parsing. A job
# that never ran reports whatever GitHub called it ("skipped", "cancelled"),
# which is the honest answer.
#
# Usage: publish_notification.sh
# Env:   TOPIC_ARN, REGION, ENVIRONMENT, VERSION, COMMIT (required)
#        LINT_RESULT, DART_RESULT, DB_RESULT, DEPLOY_RESULT, SMOKE_RESULT
#        API, RUN_URL (optional)

set -euo pipefail

: "${TOPIC_ARN:?TOPIC_ARN is required}"
: "${REGION:?REGION is required}"
: "${ENVIRONMENT:?ENVIRONMENT is required}"
: "${COMMIT:?COMMIT is required}"

VERSION="${VERSION:-${COMMIT:0:7}}"

# No column padding: SNS email is plain text, the client picks the font, and
# padded labels only line up in a monospaced one.
results=(
  "Lint: ${LINT_RESULT:-unknown}"
  "Dart tests: ${DART_RESULT:-unknown}"
  "Database tests: ${DB_RESULT:-unknown}"
  "Deploy: ${DEPLOY_RESULT:-unknown}"
  "Smoke test: ${SMOKE_RESULT:-unknown}"
)

# Anything short of a clean sweep is a failure worth saying so in the subject,
# where it is read first.
outcome="success"
for line in "${results[@]}"; do
  [[ "$line" == *": success" ]] || outcome="FAILED"
done

subject="[$ENVIRONMENT] API deploy $outcome - $VERSION"

message="Environment: $ENVIRONMENT
Version: $VERSION
Commit: $COMMIT
${API:+API: $API
}
$(printf '%s\n' "${results[@]}")
${RUN_URL:+
$RUN_URL}"

echo "Publishing to $TOPIC_ARN"
echo "$subject"

aws sns publish \
  --topic-arn "$TOPIC_ARN" \
  --subject "$subject" \
  --message "$message" \
  --region "$REGION" \
  --output text \
  --query MessageId
