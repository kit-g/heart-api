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
    appstore_app_id  = "6777837514"
    android_app_id   = "me.heart.android.dev"
    android_sha_256 = [
      # debug
      "35f7bf0fa2304cf91a52ba05492e07675380bce9f04655ca2fde7679c256342d",
      # Play's app signing key
      "46c56beea8a0b68aa6ad03ffff7da9282d5cd4711316d6faa8d0f1268c203d8e",
      # upload key
      "74aa100afd70f765fcff70d0f49bbeb6180a5368cc1f618305cf5e659cbaaa95",
    ]
    android_sha_1 = [
      # debug
      "1079f4aba98d3f8e78ab86780d86ed497d99794b",
      # Play's app signing key
      "1c54878c2b8ac0fc1858b849b8bd2d516655c9e6",
      # upload key
      "81d25bcb97f1903b82b3f0d523721b519ea4652d"
    ]
  }
}
