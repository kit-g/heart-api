#!/usr/bin/env bash
# Credential-free Terraform checks. CI (terraform-checks.yml) and `make test-tf`
# both run exactly this; keep the logic here, not in the workflow.
#
#   fmt       whole infrastructure/ tree
#   validate  every root module (any directory with a backend.tf): init without
#             a backend, then validate. This is what exercises a Dependabot
#             provider bump — init resolves the new constraint against the
#             registry, validate checks every resource block against the
#             resolved provider's schema.
#   test      every native .tftest.hcl suite (plan-only / mocked providers)
#
# Nothing here reads state or talks to AWS, Google or Supabase. A real
# `terraform plan` stays a local, credentialed step.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

# Each root is initialised into a throwaway TF_DATA_DIR rather than its own
# .terraform/: a working dir already initialised against S3 keeps that backend
# even under -backend=false, and would try to reach the state bucket. This also
# leaves the developer's real init alone. In CI nothing is initialised anyway.
DATA_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/tf-checks.XXXXXX")
trap 'rm -rf "$DATA_ROOT"' EXIT

# Lock files are gitignored, so a local one may predate the constraint being
# checked; -upgrade makes init re-resolve instead of failing on the stale lock
# (and rewrites that local, untracked lock). In CI there is no lock file.
init() {
  export TF_DATA_DIR="$DATA_ROOT/${1//\//_}"
  terraform -chdir="$1" init -backend=false -upgrade >/dev/null
}

# Share provider downloads across roots. Without a lock file Terraform ignores
# the cache unless told the lock file may be rewritten — fine, since the lock
# is not tracked anyway.
export TF_PLUGIN_CACHE_DIR="${TF_PLUGIN_CACHE_DIR:-$HOME/.terraform.d/plugin-cache}"
export TF_PLUGIN_CACHE_MAY_BREAK_DEPENDENCY_LOCK_FILE=1
export TF_IN_AUTOMATION=1
export TF_INPUT=0
mkdir -p "$TF_PLUGIN_CACHE_DIR"

# The native tests configure an aws provider with skip_credentials_validation;
# they pass with no credentials at all, but an AWS_PROFILE inherited from the
# shell that does not exist (or has expired SSO) makes the SDK bail before the
# skip flags apply. The checks are credential-free by design, so drop it.
unset AWS_PROFILE
export AWS_EC2_METADATA_DISABLED=true

echo "==> fmt"
terraform fmt -check -recursive -diff infrastructure

while IFS= read -r backend; do
  dir=$(dirname "$backend")
  echo "==> validate $dir"
  init "$dir"
  terraform -chdir="$dir" validate
done < <(find infrastructure -name backend.tf -not -path '*/.terraform/*' | sort)

# Suites live in <module>/tests/*.tftest.hcl; key on the files, not the
# directory name, so a stray empty tests/ dir does not get "tested".
while IFS= read -r dir; do
  echo "==> test $dir"
  init "$dir"
  terraform -chdir="$dir" test
done < <(find infrastructure -name '*.tftest.hcl' -not -path '*/.terraform/*' \
           -exec dirname {} \; | xargs -n1 dirname | sort -u)
