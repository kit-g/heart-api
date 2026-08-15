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

One `repo:<owner>/<name>:*` glob per repo. Listed in `stack/variables.tf` default:

- `kit-g/heart-api`
- `kit-g/heart-of-yours`

Add more by overriding `github_repos` in the env's module call.
