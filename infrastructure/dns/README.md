# DNS

Terraform for the `heart-of.me` Route 53 zone and all its records.

Single-environment by design: the apex zone lives in the dev account today and stays there even when a prod account exists later (an apex zone can only live in one place — moving it would require a registrar NS rotation). For this reason there's no `environments/` split here, just a flat stack.

## Layout

```
infrastructure/dns/
├── providers.tf       # AWS provider, profile = heart-dev
├── backend.tf         # S3 backend, separate state file
├── variables.tf       # apex domain, CloudFront distribution names
├── main.tf            # apex zone + MX/SPF/DMARC
├── dev.tf             # dev subdomain — web/media/www aliases, Firebase DKIM/SPF
├── acm.tf             # ACM cert validation CNAMEs
└── outputs.tf         # zone_id, name_servers
```

## Apply

```bash
cd infrastructure/dns
terraform init
terraform plan       # should show zero drift
terraform apply
```

## What's managed

| Record                                           | Purpose                                  |
|--------------------------------------------------|------------------------------------------|
| Zone `heart-of.me`                               | The hosted zone itself                   |
| `MX heart-of.me`                                 | improvmx mail routing                    |
| `TXT heart-of.me`                                | apex SPF + Google site verification      |
| `TXT _dmarc.heart-of.me`                         | DMARC policy                             |
| `A dev.heart-of.me`                              | alias → web CloudFront                   |
| `A www.dev.heart-of.me`                          | alias → web CloudFront                   |
| `A dev.media.heart-of.me`                        | alias → media CloudFront                 |
| `A api.heart-of.me`                              | alias → prod API Gateway (regional)      |
| `A dev.api.heart-of.me`                          | alias → dev API Gateway (regional)       |
| `TXT dev.heart-of.me`                            | Firebase mail SPF + project verification |
| `CNAME firebase{1,2}._domainkey.dev.heart-of.me` | Firebase mail DKIM                       |
| `CNAME _<hash>.dev.heart-of.me` (×4)             | ACM cert validation                      |

## Distribution domains

The web and media CloudFront distribution domain names, and the two API Gateway regional endpoints, are set in `terraform.tfvars` — the variables themselves carry no defaults. Update them when CloudFront recreates a distribution or an API Gateway domain name is recreated (both rare — alias/cert changes are in-place updates).

## ACM

ACM certs themselves are not in TF (cross-region us-east-1 + provider aliases is fiddly for little benefit). Validation CNAMEs **are** in TF — when issuing/rotating a cert, copy its validation record into `acm.tf`.

The two API certs are the exception to "everything is us-east-1": a REGIONAL API Gateway domain name only accepts a cert from its own region, so those live in `ca-central-1`, one per account. The api stack refuses any other region at plan time.

## Standing up an API domain

The zone and the app environment each hold a piece the other needs, so it is two passes:

1. Request the cert in `ca-central-1`, in that environment's account, and put its validation CNAME in `acm.tf`. Apply here; ACM issues once the record resolves.
2. Set `custom_domain` on the api module and apply that environment. It creates the domain name and the `v1` base path mapping.
3. Copy the `custom_domain.target` output into `<env>_api_domain_name` and apply here again — that is the record that makes the name resolve. Until it is set, the alias is skipped rather than half-built.

## DNS migration plan (future)

Once a prod account stands up:

1. The dev subdomain (`dev.heart-of.me`) becomes a delegated subzone in the dev account
2. dev's records move to that subzone, with the apex adding a single `NS dev.heart-of.me` delegation
3. Aliases rename: `dev.media.heart-of.me` → `media.dev.heart-of.me`, `www.dev.heart-of.me` drops
4. Apex stays in this account — prod records (`heart-of.me`, `media.heart-of.me`, etc.) get added here

Until then, this single stack manages everything.

