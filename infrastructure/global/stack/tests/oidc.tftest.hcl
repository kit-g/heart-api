provider "aws" {
  region                      = "ca-central-1"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
}

mock_provider "google-beta" {
  override_during = plan
  mock_data "google_firebase_apple_app_config" {
    defaults = { config_file_contents = "" }
  }
  mock_data "google_firebase_android_app_config" {
    defaults = { config_file_contents = "" }
  }
}

override_data {
  target = data.aws_caller_identity.this
  values = { account_id = "123456789012" }
}

override_data {
  target = data.aws_s3_object.firebase_secret
  values = { body = "{}" }
}

override_resource {
  target = aws_iam_openid_connect_provider.github
  values = {
    id  = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
    arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
  }
}

variables {
  github_oidc_subjects = [
    "repo:kit-g/heart-api:ref:refs/heads/main",
    "repo:kit-g/heart-api:ref:refs/tags/v*",
  ]
  static_bucket         = "static"
  buckets               = ["content"]
  web_distribution_id   = "WEB"
  media_distribution_id = "MEDIA"
  agent_roles           = []
  firebase_project_config = {
    project_id       = "test-project"
    region           = "us-central1"
    ios_bundle_id    = "me.heart.test"
    appstore_team_id = "TEST"
    appstore_app_id  = "123"
    android_app_id   = "me.heart.test"
    android_sha_256  = []
    android_sha_1    = []
  }
}

# Only this overridden resource enters the test state. The subsequent plan
# can then render the real IAM document locally instead of deferring it.
run "mock_oidc_provider" {
  command = apply
  plan_options {
    target = [aws_iam_openid_connect_provider.github]
  }
}

run "trust_is_limited_to_the_explicit_ref_subjects" {
  command = plan

  assert {
    condition = toset(
      jsondecode(data.aws_iam_policy_document.trust.json).Statement[0].Condition.StringLike["token.actions.githubusercontent.com:sub"]
    ) == toset(var.github_oidc_subjects)
    error_message = "The rendered IAM policy must preserve the exact ref restrictions."
  }

  assert {
    condition = (
      jsondecode(data.aws_iam_policy_document.trust.json).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:aud"]
      == "sts.amazonaws.com"
    )
    error_message = "Only the AWS STS audience may assume the role."
  }
}

run "dev_allows_repository_wide_trust" {
  command = plan
  variables {
    github_oidc_subjects = ["repo:kit-g/heart-api:*", "repo:kit-g/heart-of-yours:*"]
  }

  assert {
    condition = toset(
      jsondecode(data.aws_iam_policy_document.trust.json).Statement[0].Condition.StringLike["token.actions.githubusercontent.com:sub"]
    ) == toset(var.github_oidc_subjects)
    error_message = "Dev must accept all contexts of the two named repositories."
  }
}

run "reject_wildcard_repository_trust" {
  command = plan
  variables {
    github_oidc_subjects = ["repo:kit-g/*:*"]
  }
  expect_failures = [var.github_oidc_subjects]
}
