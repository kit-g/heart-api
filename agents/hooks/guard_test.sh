#!/bin/bash
# Regression matrix for guard.sh. Run: agents/hooks/guard_test.sh
# Each case: expected decision, a tab, the command as the Bash tool would see it.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
fail=0
while IFS=$'\t' read -r want cmd; do
  [[ -z "$want" || "$want" == \#* ]] && continue
  out="$(jq -n --arg c "$cmd" '{tool_input:{command:$c}}' | "$HERE/guard.sh")"
  got=allow; [[ -n "$out" ]] && got=deny
  mark=ok; [[ "$got" != "$want" ]] && { mark=FAIL; fail=1; }
  printf '%-4s %-5s %s\n' "$mark" "$got" "$cmd"
done <<'EOF2'
# never-commit rule
deny	git commit -m x
deny	git push origin main
deny	git push --tags
deny	git -C /Users/kitg/mine/heart-api push origin main
deny	cd x && git commit -m y
deny	echo hi; git push
deny	out=$(git merge main)
# work-destroying git
deny	git merge main
deny	git merge
deny	git -C /x merge --no-ff feature
deny	git rebase main
deny	git rebase -i HEAD~3
deny	git reset --hard HEAD
deny	git checkout .
deny	git restore .
deny	git stash drop
deny	git branch -D feature
deny	git clean -fd
# read-only git that used to trip the subcommand match
allow	git log --oneline -15 --merges
allow	git log --no-merges main..HEAD
allow	git merge-base main HEAD
allow	git -C .claude/worktrees/a1 log --oneline main..HEAD
allow	git status --short
allow	git worktree list
allow	git add -N .
allow	git tag --list 'v*'
# git mentioned in prose, not in command position
allow	echo git subcommand merge text in a script
allow	cat file.md | grep 'git commit'
allow	grep -n 'git push' agents/README.md
# rm
deny	rm -rf api/lib
allow	rm -rf build/
allow	rm -rf .dart_tool
allow	rm -rf api/.dart_tool
allow	rm -rf .venv
allow	rm -rf infrastructure/app/environments/dev/.terraform
allow	rm -rf /tmp/tf-checks.abc
deny	rm -rf build_tools
deny	rm -rf api/.dart_toolkit
# terraform: plan/validate yes, apply no
allow	terraform -chdir=infrastructure/app/environments/dev plan
allow	terraform -chdir=infrastructure/app/environments/dev init -backend=false
allow	terraform validate
allow	terraform fmt -check -recursive infrastructure
allow	terraform providers lock -platform=linux_amd64
allow	terraform -chdir=infrastructure/dns state list
allow	terraform -chdir=infrastructure/dns state show aws_route53_zone.this
allow	make test-tf
deny	terraform apply
deny	terraform -chdir=infrastructure/app/environments/dev apply -auto-approve
deny	terraform destroy -target=aws_sqs_queue.events
deny	terraform -chdir=infrastructure/dns state rm aws_route53_record.a
deny	terraform import aws_iam_role.agent heart-agent
deny	terraform force-unlock 1234
# migrations only against localhost
allow	make test-db
allow	make db-seed
allow	PGHOST=localhost PGDATABASE=heart ./scripts/apply_migrations.sh
allow	PGHOST=host.docker.internal ./scripts/apply_migrations.sh
allow	cat scripts/apply_migrations.sh
allow	grep -n PGHOST scripts/apply_migrations.sh
deny	bash scripts/apply_migrations.sh
deny	./scripts/apply_migrations.sh
deny	cd scripts && ./apply_migrations.sh
deny	PGDATABASE=heart ./scripts/apply_migrations.sh
# prod stays out of reach
deny	AWS_PROFILE=heart-prod aws lambda get-function --function-name heart-api
deny	aws --profile heart-prod sts get-caller-identity
deny	aws sts get-caller-identity --profile=heart-prod
allow	AWS_PROFILE=heart-dev aws sts get-caller-identity
# aws: reads yes, writes no
allow	aws sqs get-queue-attributes --queue-url $Q --attribute-names All
allow	aws logs filter-log-events --log-group-name /aws/lambda/heart-api --limit 50
allow	aws lambda get-function-configuration --function-name heart-api
allow	aws s3 ls s3://583168578067-ca-central-1-content/
allow	aws s3 cp s3://583168578067-ca-central-1-content/library.json /tmp/library.json
allow	aws s3api list-objects-v2 --bucket 583168578067-ca-central-1-content
allow	aws cloudfront get-distribution --id ETG4S2WYJRREX
allow	aws scheduler list-schedules
deny	aws lambda update-function-code --function-name heart-api --zip-file fileb://api.zip
deny	aws lambda invoke --function-name heart-api /tmp/out.json
deny	aws sqs purge-queue --queue-url $Q
deny	aws sqs send-message --queue-url $Q --message-body '{}'
deny	aws s3 cp /tmp/x.json s3://583168578067-ca-central-1-content/x.json
deny	aws s3 sync content/ s3://583168578067-ca-central-1-content/
deny	aws s3 rm s3://583168578067-ca-central-1-content/x.json
deny	aws s3api put-object --bucket b --key k --body f
deny	aws cloudfront create-invalidation --distribution-id ETG4S2WYJRREX --paths '/*'
deny	aws scheduler delete-schedule --name x
deny	aws iam attach-role-policy --role-name heart-agent --policy-arn arn:x
deny	aws sts assume-role --role-arn arn:x --role-session-name s
EOF2
[[ $fail -eq 0 ]] && echo "all cases pass"
exit $fail
