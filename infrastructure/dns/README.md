# DNS — the old apex zone, and the runbook for leaving it

This root manages the single `heart-of.me` zone in the **dev** account, which served both
environments until heart-api#142. Its replacement is in place: prod's apex zone in
`app/environments/prod/dns.tf`, dev's zone `dev.heart-of.me` in `app/environments/dev/dns.tf`,
and every certificate issued by its own environment (`docs/2026-10-08.dns-split.md`). This zone
keeps answering the apex until the registrar points at prod's; then this directory goes.

The move is in two halves. The dev subtree moves first, live, by delegating `dev.heart-of.me`
from this zone (phases 1–3): that is where dev's hosts are renamed, and dev builds break until
their env files follow. The apex moves second (phases 4–7), and nothing public changes there until
the registrar switch, which swaps between two zones serving the same answers.

## 1. dev — the zone, and what it can carry before it is delegated

```bash
cd infrastructure/app/environments/dev
terraform apply \
  -target=aws_route53_zone.dev \
  -target=aws_route53_record.firebase_txt \
  -target=aws_route53_record.firebase_dkim
terraform output name_servers
```

Creates the zone with Firebase's mail records. Nothing public changes: nothing delegates to the
zone yet. Only these three targets: the alias records share one `for_each` over every stack
output, so targeting any one of them drags in the API domain name and with it the api
certificate, whose validation record only this zone carries — the apply then waits on a record
nobody can resolve. If that has happened, do not cancel: run phase 2 in another terminal (its
state is separate), and the wait ends by itself once the delegation is live.

## 2. this root — delegate dev, drop its records

Put the four servers from dev's `name_servers` into `dev_name_servers` in `terraform.tfvars`, then:

```bash
cd infrastructure/dns
terraform plan      # 1 to add (the NS record), 12 to destroy (dev's records and the dev validation CNAMEs)
terraform apply
```

From here the dev subtree is the new zone's. Firebase's dev mail records are already there;
`dev.heart-of.me` and `www.dev.heart-of.me` are dark until the next phase puts their aliases in,
minutes. `dev.api.heart-of.me` and `dev.media.heart-of.me` stop resolving for good: that is the
accepted break, and they come back under their new names in the next phase.

## 3. dev — the rest

```bash
cd infrastructure/app/environments/dev
terraform plan      # 19 to add in total with phase 1, 4 to change, 2 to destroy (the API domain name and its mapping, replaced)
terraform apply
```

Requests and validates the certificates for `api.dev.heart-of.me` and `media.dev.heart-of.me`
(ACM issues within minutes once the records resolve), puts the web aliases in, recreates the API's domain name and base
path mapping under the new name, re-aliases the media distribution, and points both aliases.
The Lambda functions pick up the new names in their environment.

Then, outside this repo: the app's `env/dev.json`, `env/new-dev.json` and `env/local.json`
(gitignored) name `API` and `MEDIA_LINK`; change them to `api.dev.heart-of.me` and
`media.dev.heart-of.me`. Dev builds made before that cannot reach the API or media again. The
site's dev config and OAuth metadata (`site/connect/dev.js`, `site/.well-known/dev/`) are in this
change and ship with the next site deploy.

## 4. prod — the apex, its certificates, the delegation

Put the same four servers into `dev_name_servers` in `app/environments/prod/terraform.tfvars`,
then:

```bash
cd infrastructure/app/environments/prod
terraform plan      # 4 to import, 0 to destroy; nothing in module.cdn or module.api
terraform apply
terraform output name_servers
```

Creates the apex zone (not yet authoritative for anyone), its alias, mail and verification records,
the NS delegation for `dev.heart-of.me`, and imports the four prod certificates. The plan's only
changes to existing resources are the default tags landing on the certificates.

ACM's renewal of `media.heart-of.me` and `heart-of.me` is due to start around 2026-10-11 (sixty
days before expiry on 2026-12-10). It validates against whichever zone the public resolvers reach,
and both carry the records, so the move does not need to wait for it or hurry past it.

## 5. Compare the two apex zones

Every apex name, from the old servers and from the new, before the switch. The dev names are not
listed: both zones delegate them to the same place by now.

```bash
OLD=ns-466.awsdns-58.com
NEW=$(cd infrastructure/app/environments/prod && terraform output -json name_servers | jq -r '.[0]')

while read -r name type; do
  printf '%-36s %-5s old: %s\n%-42s new: %s\n' "$name" "$type" \
    "$(dig +short @"$OLD" "$name" "$type" | sort | tr '\n' ' ')" "" \
    "$(dig +short @"$NEW" "$name" "$type" | sort | tr '\n' ' ')"
done <<LIST
heart-of.me                       A
heart-of.me                       MX
heart-of.me                       TXT
heart-of.me                       NS
dev.heart-of.me                   NS
_dmarc.heart-of.me                TXT
firebase1._domainkey.heart-of.me  CNAME
firebase2._domainkey.heart-of.me  CNAME
www.heart-of.me                   A
api.heart-of.me                   A
media.heart-of.me                 A
mcp.heart-of.me                   A
LIST
```

The alias records answer with CloudFront or API Gateway addresses, which rotate between queries;
for those, both sides answering with the same kind of address is the match. The apex `NS` differs
by design (each zone names its own servers); everything else has to be byte-for-byte. The ACM
validation CNAMEs are not listed: the certificate modules put them in the new zone from the
certificates themselves, and the apply would have failed otherwise.

## 6. The registrar

The domain is registered through Route 53 Domains in the dev account (Gandi is the registrar AWS
uses for `.me`, which is what WHOIS shows). Point it at prod's four:

```bash
aws route53domains update-domain-nameservers --profile heart-dev --region us-east-1 \
  --domain-name heart-of.me \
  --nameservers Name=<ns1> Name=<ns2> Name=<ns3> Name=<ns4>
dig +trace heart-of.me NS | tail -6     # the .me servers now answer with prod's four
```

The registration itself stays in the dev account; moving it to prod is a separate transfer, for
another day.

Resolvers pick up the change as the `.me` delegation's TTL expires (a day), and some cache beyond
it. Nothing blinks in between: both zones answer the same.

## 7. Retire this zone

No sooner than 48 hours after the switch:

1. Remove the `prevent_destroy` lifecycle from `main.tf`.
2. `terraform destroy` here. It takes the old zone and every record still in it.
3. Delete `infrastructure/dns/`, its line in `infrastructure/README.md`, and this file with it.
   The state object `heart/dns/terraform.tfstate` in the dev state bucket can go too.
4. In the dev account's ACM, delete the certificates nothing uses any more: in us-east-1 the
   `media.dev.heart-of.me` one issued by hand in September with the wrong set of names
   (`725a40da…`, renewal-ineligible, expires 2026-11-23) and the old `dev.media.heart-of.me` one
   (`297c34bc…`); in ca-central-1 the old `dev.api.heart-of.me` one (`43e5a2aa…`). Phase 3
   detached all three.
