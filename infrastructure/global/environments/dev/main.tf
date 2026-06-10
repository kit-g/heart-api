module "deploy_role" {
  source              = "../../stack"
  buckets             = ["583168578067-ca-central-1-content"]
  static_bucket       = "583168578067-ca-central-1-static"
  web_distribution_id = "E1WWZSFXKW7BW7"
  firebase_project_config = {
    project_id       = "heart-of-yours-dev"
    region           = "us-central1"
    ios_bundle_id    = "me.heart-of.ios.dev"
    appstore_team_id = "DFX2JYT8BM"
    android_app_id   = "me.heart.android.dev"
  }
}
