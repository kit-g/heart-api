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
| `TXT dev.heart-of.me`                            | Firebase mail SPF + project verification |
| `CNAME firebase{1,2}._domainkey.dev.heart-of.me` | Firebase mail DKIM                       |
| `CNAME _<hash>.dev.heart-of.me` (×4)             | ACM cert validation                      |

## Distribution domains

The web and media CloudFront distribution domain names are hardcoded in `variables.tf` defaults. Update them when CloudFront recreates a distribution (which is rare — alias/cert changes are in-place updates).

## ACM

ACM certs themselves are not in TF (cross-region us-east-1 + provider aliases is fiddly for little benefit). Validation CNAMEs **are** in TF — when issuing/rotating a cert, copy its validation record into `acm.tf`.

## DNS migration plan (future)

Once a prod account stands up:

1. The dev subdomain (`dev.heart-of.me`) becomes a delegated subzone in the dev account
2. dev's records move to that subzone, with the apex adding a single `NS dev.heart-of.me` delegation
3. Aliases rename: `dev.media.heart-of.me` → `media.dev.heart-of.me`, `www.dev.heart-of.me` drops
4. Apex stays in this account — prod records (`heart-of.me`, `media.heart-of.me`, etc.) get added here

Until then, this single stack manages everything.

