module "deploy_role" {
  source              = "../../stack"
  static_bucket       = "922419543441-ca-central-1-static"
  buckets             = ["922419543441-ca-central-1-content"]
  web_distribution_id = "ETG4S2WYJRREX"
  firebase_project_config = {
    project_id = "heart-of-yours"
    region     = "us-central1"
  }
}
