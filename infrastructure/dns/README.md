# DNS — the old apex zone, and the runbook for leaving it

This root manages the single `heart-of.me` zone in the **dev** account, which served both
environments until heart-api#142. Its replacement is in place: prod's apex zone in
`app/environments/prod/dns.tf`, dev's three zones in `app/environments/dev/dns.tf`, and every
certificate issued by its own environment (`docs/2026-10-08.dns-split.md`). This zone keeps
answering until the registrar points at prod's; then this directory goes.

**Do not change records here while the move is in flight.** Both zones have to serve identical
answers for the switch to be invisible, and this one is the copy.

## The move

Phases 1–2 change nothing public: no delegation exists yet, and the registrar still names this
zone's servers. The NS switch (phase 4) is the only step that is live, and it is a swap between two
zones serving the same answers.

### 1. dev — its zones, its certificates

```bash
cd infrastructure/app/environments/dev
terraform plan      # 3 to import, 18 to add, 3 to change (tags on the certificates), 0 to destroy
terraform apply
terraform output name_servers
```

Creates the delegation set, the zones `dev.heart-of.me`, `dev.api.heart-of.me` and
`dev.media.heart-of.me`, their alias and Firebase records, and imports the three dev certificates
with their validation records beside them. Nothing in `module.cdn` or `module.api` changes: the
distributions and the domain name keep the certificates they hold.

### 2. prod — the apex, its certificates, the delegations

Put the four servers from dev's `name_servers` into `dev_name_servers` in
`app/environments/prod/terraform.tfvars`, then:

```bash
cd infrastructure/app/environments/prod
terraform plan      # 4 to import, 0 to destroy; nothing in module.cdn or module.api
terraform apply
terraform output name_servers
```

Creates the apex zone (not yet authoritative for anyone), its alias, mail and verification records,
the three NS delegations, and imports the four prod certificates. The plan's only changes to
existing resources are the default tags landing on the certificates.

ACM's renewal of `media.heart-of.me` and `heart-of.me` is due to start around 2026-10-11 (sixty
days before expiry on 2026-12-10). It validates against whichever zone the public resolvers reach,
and both carry the records, so the move does not need to wait for it or hurry past it.

### 3. Compare the two zones

Every name, from the old servers and from the new, before the switch. The dev names are delegated
in prod's zone, so they are asked of dev's servers directly.

```bash
OLD=ns-466.awsdns-58.com
NEW=$(cd infrastructure/app/environments/prod && terraform output -json name_servers | jq -r '.[0]')
DEV=$(cd infrastructure/app/environments/dev && terraform output -json name_servers | jq -r '.[0]')

while read -r name type server; do
  printf '%-40s %-5s old: %s\n%-46s new: %s\n' "$name" "$type" \
    "$(dig +short @"$OLD" "$name" "$type" | sort | tr '\n' ' ')" "" \
    "$(dig +short @"$server" "$name" "$type" | sort | tr '\n' ' ')"
done <<LIST
heart-of.me                       A     $NEW
heart-of.me                       MX    $NEW
heart-of.me                       TXT   $NEW
_dmarc.heart-of.me                TXT   $NEW
firebase1._domainkey.heart-of.me  CNAME $NEW
firebase2._domainkey.heart-of.me  CNAME $NEW
www.heart-of.me                   A     $NEW
api.heart-of.me                   A     $NEW
media.heart-of.me                 A     $NEW
mcp.heart-of.me                   A     $NEW
dev.heart-of.me                   A     $DEV
dev.heart-of.me                   TXT   $DEV
www.dev.heart-of.me               A     $DEV
dev.api.heart-of.me               A     $DEV
dev.media.heart-of.me             A     $DEV
firebase1._domainkey.dev.heart-of.me CNAME $DEV
firebase2._domainkey.dev.heart-of.me CNAME $DEV
LIST
```

The alias records answer with CloudFront or API Gateway addresses, which rotate between queries;
for those, both sides answering with the same kind of address is the match. Everything else has to
be byte-for-byte. The ACM validation CNAMEs are not listed: the certificate modules put them in the
new zones from the certificates themselves, and the apply would have failed otherwise.

### 4. The registrar

At Gandi, replace the domain's name servers with prod's four. Then:

```bash
dig +trace heart-of.me NS | tail -6     # the .me servers now answer with prod's four
```

Resolvers pick up the change as the `.me` delegation's TTL expires (a day), and some cache beyond
it. Nothing blinks in between: both zones answer the same.

### 5. Retire this zone

No sooner than 48 hours after the switch:

1. Remove the `prevent_destroy` lifecycle from `main.tf`.
2. `terraform destroy` here. It takes the old zone and every record in it, including the
   validation CNAME for the unused `media.dev.heart-of.me` certificate, which nothing imported.
3. Delete `infrastructure/dns/`, its line in `infrastructure/README.md`, and this file with it.
   The state object `heart/dns/terraform.tfstate` in the dev state bucket can go too.
4. In the dev account's ACM (us-east-1), delete that unused `media.dev.heart-of.me` certificate;
   it is renewal-ineligible and expires 2026-11-23 regardless.
