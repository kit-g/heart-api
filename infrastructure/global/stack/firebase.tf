terraform {
  required_providers {
    # No version here on purpose. Both environments wire this one module, so
    # a constraint in this file made Dependabot open the same one-line PR
    # twice (once per environment directory it watches). Each environment
    # pins google-beta in its own providers.tf instead.
    google-beta = {
      source = "hashicorp/google-beta"
    }
  }
}

data "aws_s3_object" "firebase_secret" {
  bucket = var.static_bucket
  key    = "secrets/firebase/firebase-terraform-sa.json"
}

provider "google-beta" {
  credentials = data.aws_s3_object.firebase_secret.body
  project     = var.firebase_project_config.project_id
  region      = var.firebase_project_config.region
}

resource "google_project_service" "firebase" {
  provider           = google-beta
  project            = var.firebase_project_config.project_id
  service            = "firebase.googleapis.com"
  disable_on_destroy = false
}

resource "google_firebase_project" "default" {
  provider   = google-beta
  project    = var.firebase_project_config.project_id
  depends_on = [google_project_service.firebase]
}

resource "google_firebase_apple_app" "ios" {
  provider     = google-beta
  project      = var.firebase_project_config.project_id
  display_name = "Heart iOS App"
  bundle_id    = var.firebase_project_config.ios_bundle_id
  team_id      = var.firebase_project_config.appstore_team_id
  app_store_id = var.firebase_project_config.appstore_app_id
  depends_on   = [google_firebase_project.default]
}

resource "google_firebase_android_app" "android" {
  provider      = google-beta
  project       = var.firebase_project_config.project_id
  display_name  = "Heart Android App"
  package_name  = var.firebase_project_config.android_app_id
  depends_on    = [google_firebase_project.default]
  sha256_hashes = var.firebase_project_config.android_sha_256
  sha1_hashes   = var.firebase_project_config.android_sha_1
}

data "google_firebase_apple_app_config" "ios" {
  provider = google-beta
  app_id   = google_firebase_apple_app.ios.app_id
}

data "google_firebase_android_app_config" "android" {
  provider = google-beta
  app_id   = google_firebase_android_app.android.app_id
}

# we'll store the config files in S3 for now and both the app and CI will find it there
resource "aws_s3_object" "ios_firebase_config" {
  bucket       = var.static_bucket
  key          = "secrets/firebase/GoogleService-Info.plist"
  content      = base64decode(data.google_firebase_apple_app_config.ios.config_file_contents)
  content_type = "application/xml"
}

resource "aws_s3_object" "android_firebase_config" {
  bucket       = var.static_bucket
  key          = "secrets/firebase/google-services.json"
  content      = base64decode(data.google_firebase_android_app_config.android.config_file_contents)
  content_type = "application/json"
}

# Terraform's calls bill to this project, not gcloud's quota project, so the
# service account resources below fail without it. Enabled by hand once before
# the import: imports read at plan time, ahead of any apply that could enable it.
resource "google_project_service" "iam" {
  provider           = google-beta
  project            = var.firebase_project_config.project_id
  service            = "iam.googleapis.com"
  disable_on_destroy = false
}

# For heart-agent's calls to the GA4 Admin API (custom definitions, key events).
# Its access to the linked GA4 property is granted in the Analytics UI, as a
# property Editor; no Terraform resource covers that.
resource "google_project_service" "analytics_admin" {
  provider           = google-beta
  project            = var.firebase_project_config.project_id
  service            = "analyticsadmin.googleapis.com"
  disable_on_destroy = false
}

# Identity for autonomous coding agents working on the app's Firebase side.
# Created by hand in both projects and later imported into state.
# Unlike the AWS agent role (environments/dev/agent.tf) it exists in prod too;
# roles differ per project, so each environment passes its own list.
resource "google_service_account" "agent" {
  provider     = google-beta
  project      = var.firebase_project_config.project_id
  account_id   = "heart-agent"
  display_name = "Heart agent"
  depends_on   = [google_project_service.iam]
}

resource "google_project_iam_member" "agent" {
  provider = google-beta
  for_each = toset(var.agent_roles)
  project  = var.firebase_project_config.project_id
  role     = each.value
  member   = google_service_account.agent.member
}
