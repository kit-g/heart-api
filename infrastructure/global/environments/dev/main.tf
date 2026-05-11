module "deploy_role" {
  source              = "../../stack"
  buckets             = ["583168578067-ca-central-1-content"]
  static_bucket       = "583168578067-ca-central-1-static"
  web_distribution_id = "E1WWZSFXKW7BW7"
}
