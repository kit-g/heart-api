# Account-tier resources

Account-tier resources — GitHub OIDC provider + the deploy role each account's workflows assume. Same shape as `infrastructure/app/`: a reusable `stack/` module plus per-account `environments/`. Each AWS account gets its own deploy of this stack.

The dev environment additionally defines `heart-agent` (`environments/dev/agent.tf`) — a read-only role for autonomous coding agents, assumable only by the developer's dev-account IAM user. Dev-only by construction; its ARN goes in `AGENT_AWS_ROLE_ARN` in `~/.config/heart-agents/default.env` on the dev machine, never in a repo.

## Layout

```
infrastructure/ci/
├── stack/                  # Reusable module — OIDC provider + role + policies
└── environments/
    ├── dev/
    └── prod/               
```

## Trust policy

Each environment supplies explicit `github_oidc_subjects` for main and its
release-tag prefixes. Pull requests, feature branches and environment-shaped
subjects are not trusted.

Dev permits heart-api main and heart-of-yours main, v* and dev-* tags. Prod permits
heart-api main (the intentional assets exception) and v* tags, plus heart-of-yours
main, v*, ios* and android* tags. Manual deploys must run from one of those refs.
The frontend deployment jobs currently have no GitHub environment attached; an
environment input alone does not change the OIDC subject.

Apply the account-tier trust changes before running the updated workflows.
Test and validation jobs have only contents:read; only deploy/notification jobs
request id-token:write. Repository/ref restrictions remain necessary even with
those job permissions, because a PR can edit its own workflow.
