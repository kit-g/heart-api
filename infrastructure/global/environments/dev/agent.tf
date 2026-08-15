# Role for autonomous coding agents. Deliberately defined here rather than in
# the shared stack module: it is dev-only and must not exist in prod.
#
# The agent launcher on the dev machine assumes this role with the developer's
# own `heart-dev` profile and injects the short-lived STS session credentials
# into agent containers — no long-lived agent secret exists anywhere. The role
# ARN is expected to land in AGENT_AWS_ROLE_ARN in
# ~/.config/heart-agents/default.env on the dev machine, never in a repo.
#
# Read-only to start. When a task genuinely needs a write (redriving a dev
# queue, invoking a dev Lambda), add a narrow inline policy naming those ARNs
# then — nothing is pre-granted.

data "aws_iam_policy_document" "agent_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::583168578067:user/Kit"]
    }
  }
}

resource "aws_iam_role" "agent" {
  name               = "heart-agent"
  assume_role_policy = data.aws_iam_policy_document.agent_trust.json
  # the launcher requests 4h by default but may go longer for big tasks
  max_session_duration = 43200
}

resource "aws_iam_role_policy_attachment" "agent_read_only" {
  role       = aws_iam_role.agent.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

output "agent_role_arn" {
  value = aws_iam_role.agent.arn
}
