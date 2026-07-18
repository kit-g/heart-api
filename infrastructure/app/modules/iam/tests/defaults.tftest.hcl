# Tests for the reusable IAM role module.
#
# Run from this module's directory:  terraform init && terraform test
#
# These are plan-only tests: they never call AWS. The assume-role policy is
# rendered locally by the aws_iam_policy_document data source, so we can assert
# on real output with no credentials and no resources created.

# The module has no provider block of its own (callers supply one), so the test
# supplies a region-only provider. No credentials are used at plan time.
provider "aws" {
  region                      = "ca-central-1"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
}

run "defaults_trust_lambda" {
  command = plan

  variables {
    name = "heart-api-function-role"
  }

  assert {
    condition     = aws_iam_role.this.name == "heart-api-function-role"
    error_message = "Role name should equal the name variable"
  }

  # Default service principal is lambda.amazonaws.com.
  assert {
    condition     = strcontains(data.aws_iam_policy_document.assume_role.json, "lambda.amazonaws.com")
    error_message = "Default assume-role policy must trust lambda.amazonaws.com"
  }

  # With no inline or managed policies passed, none should be planned.
  assert {
    condition     = length(aws_iam_role_policy.inline) == 0
    error_message = "No inline policies expected by default"
  }
  assert {
    condition     = length(aws_iam_role_policy_attachment.managed) == 0
    error_message = "No managed policy attachments expected by default"
  }
}

run "custom_principals_and_inline_policies" {
  command = plan

  variables {
    name               = "heart-api-scheduler-role"
    service_principals = ["scheduler.amazonaws.com"]
    inline_policies = {
      send_sqs = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":\"sqs:SendMessage\",\"Resource\":\"*\"}]}"
    }
  }

  assert {
    condition     = strcontains(data.aws_iam_policy_document.assume_role.json, "scheduler.amazonaws.com")
    error_message = "Assume-role policy must trust the overridden principal"
  }

  # Inline policies are keyed by map key; the resource address proves the
  # for_each wired the key through as the policy name.
  assert {
    condition     = aws_iam_role_policy.inline["send_sqs"].name == "send_sqs"
    error_message = "Inline policy should be named after its map key"
  }
}
