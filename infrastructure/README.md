# Infrastructure

Terraform for everything AWS + Supabase.

## Layout

```
infrastructure/
├── stacks/
│   ├── api/             # Lambda function, API Gateway, SQS events queue + DLQ,
│   │                    # EventBridge S3 rule, Scheduler group, SNS monitoring topic,
│   │                    # IAM roles, CloudWatch logs
│   ├── cdn/             # CloudFront media + web distributions, OACs, S3 bucket policies
│   ├── content/         # Content + static S3 buckets, lifecycle for uploads/,
│   │                    # EventBridge bucket notification, Supabase project
│   ├── platform/dns/    # Apex zone + email + NS delegations (not deployed yet — waits for prod)
│   └── app/dns/         # Per-env subzone + records (not deployed yet)
├── modules/
│   └── iam/             # Reusable role + inline-policies wrapper
└── environments/
    └── dev/             # Wires the stacks for the dev account
```

## Deployment

```bash
cd infrastructure/environments/dev
terraform init
terraform plan
terraform apply
```

The dev environment auto-builds the Lambda binary on `terraform apply` (via `null_resource.build_dart_api` in `stacks/api/archives.tf`) — no separate build step needed for infra-only applies.

## Conventions

### Path references inside stacks

- **Module sources between siblings**: relative paths like `../../stacks/api`. Uniform; survives directory restructures.
- **Repo references inside a stack** (e.g. `archives.tf` reaching `api/`): `${path.module}/../../../api`. Three levels up from `infrastructure/stacks/<stack>/` is the repo root.

### Naming

Resources use `${var.name_prefix}-<thing>`. In dev, `name_prefix = "heart-api"` produces `heart-api-events`, `heart-api-events-dlq`, `heart-api-function-role`. Lambda function name itself is bare `heart-api`.

### IAM scoping

EventBridge Scheduler distinguishes two ARN shapes that look similar but aren't interchangeable:

| What | ARN format |
|---|---|
| Schedule group (collection) | `arn:aws:scheduler:<region>:<account>:schedule-group/<group>` |
| Schedule (individual) | `arn:aws:scheduler:<region>:<account>:schedule/<group>/<name>` |

`scheduler:CreateSchedule` / `DeleteSchedule` operate on the **schedule** (second form). Scoping a policy to the schedule-group ARN won't grant access — the resource has to be `schedule/<group>/*`.

Cross-service `iam:PassRole` is required when the API Lambda creates a schedule that targets SQS via the scheduler IAM role — see `stacks/api/roles.tf`.

### ACM

Certificate ARNs are passed in as variables, not managed in TF. Cross-region ACM (us-east-1 for CloudFront) provider aliases are fiddly, and certs change rarely — keep them out.

### DNS

`stacks/platform/dns/` and `stacks/app/dns/` exist as scaffolding but aren't wired in any environment yet. The DNS migration waits until a prod account exists — the current single-account dev setup doesn't need the platform/app split.

When the prod account stands up:
1. Apex zone (`heart-of.me`) lives in prod, owns email records + delegations
2. `dev.heart-of.me` becomes a delegated subzone in the dev account
3. Aliases rename: `dev.media.heart-of.me` → `media.dev.heart-of.me`, etc.

## State

Backend is S3 (`583168578067-us-east-2-tfstate`) with DynamoDB locking (`tfstate-locks`). One state file per environment under `heart/<env>/terraform.tfstate`.

`.terraform.lock.hcl` and any `*.tfvars` are gitignored.
