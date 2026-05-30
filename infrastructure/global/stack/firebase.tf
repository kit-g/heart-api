terraform {
  required_providers {
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }
  }
}

data "aws_s3_object" "firebase_secret" {
  bucket = var.static_bucket
  key    = "secrets/firebase-terraform-sa.json"
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

