module "deploy_role" {
  source              = "../../stack"
  buckets             = ["583168578067-us-east-2-content"]
  static_bucket       = "583168578067-us-east-2-static"
  web_distribution_id = "E1WWZSFXKW7BW7"
}
