locals {
  account_id = data.aws_caller_identity.this.account_id
  region     = data.aws_region.this.region

  static_bucket_arn = "arn:aws:s3:::${var.static_bucket}"
  bucket_arns       = [for b in var.buckets : "arn:aws:s3:::${b}"]
  bucket_objects    = [for b in var.buckets : "arn:aws:s3:::${b}/*"]
}


resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]

  thumbprint_list = []
  lifecycle {
    ignore_changes = [thumbprint_list]
  }
}

data "aws_iam_policy_document" "trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [for r in var.github_repos : "repo:${r}:*"]
    }
  }
}

resource "aws_iam_role" "deploy" {
  name               = "heart-github-actions-deploy-role"
  assume_role_policy = data.aws_iam_policy_document.trust.json
}

data "aws_iam_policy_document" "lambda" {
  statement {
    effect = "Allow"
    actions = [
      "lambda:UpdateFunctionCode",
      "lambda:GetFunction",
      "lambda:GetFunctionConfiguration",
    ]
    resources = ["arn:aws:lambda:${local.region}:${local.account_id}:function:${var.lambda_function_prefix}*"]
  }
}

resource "aws_iam_role_policy" "lambda" {
  name   = "lambda-deployment"
  role   = aws_iam_role.deploy.id
  policy = data.aws_iam_policy_document.lambda.json
}

data "aws_iam_policy_document" "static_bucket" {
  statement {
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${local.static_bucket_arn}/*"]
  }
  statement {
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = ["${local.static_bucket_arn}/site/*"]
  }
  statement {
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [local.static_bucket_arn]
  }
}

resource "aws_iam_role_policy" "static_bucket" {
  name   = "static-bucket"
  role   = aws_iam_role.deploy.id
  policy = data.aws_iam_policy_document.static_bucket.json
}

data "aws_iam_policy_document" "exercise_library" {
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = local.bucket_objects
  }
  statement {
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = local.bucket_arns
  }
}

resource "aws_iam_role_policy" "exercise_library" {
  name   = "exercise-library"
  role   = aws_iam_role.deploy.id
  policy = data.aws_iam_policy_document.exercise_library.json
}

data "aws_iam_policy_document" "cloudfront" {
  statement {
    effect    = "Allow"
    actions   = ["cloudfront:CreateInvalidation"]
    resources = ["arn:aws:cloudfront::${local.account_id}:distribution/${var.web_distribution_id}"]
  }
}

resource "aws_iam_role_policy" "cloudfront" {
  name   = "cloudfront-invalidation"
  role   = aws_iam_role.deploy.id
  policy = data.aws_iam_policy_document.cloudfront.json
}
