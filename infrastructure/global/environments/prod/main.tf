module "deploy_role" {
  source                = "../../stack"
  static_bucket         = "922419543441-ca-central-1-static"
  buckets               = ["922419543441-ca-central-1-content"]
  web_distribution_id   = "ETG4S2WYJRREX"
  media_distribution_id = "EGZ95J4EWTC39"
  firebase_project_config = {
    project_id       = "heart-of-yours"
    region           = "us-central1"
    ios_bundle_id    = "me.heart-of.ios"
    appstore_app_id  = "6777837444"
    appstore_team_id = "DFX2JYT8BM"
    android_app_id   = "me.heart.android"
    android_sha_256 = [
      # Play's app signing key
      "005da98a25539ba22934a2fc61ff6702f6f9dcb1849aeafa0877540dd461d5b0",
      # upload key
      "51da9c56425dd2db263b21284c3d6a7c51bdc489073316a6ab5076a90913f5ee"
    ]
    android_sha_1 = [
      # debug
      "1079f4aba98d3f8e78ab86780d86ed497d99794b",
      # Play's app signing key
      "ec2ec2bde1b4e083246b28ed5d69e4b12d813000",
      # upload key
      "726f8ed3f780da2a9a6f084b7ae9a04f5352bdeb"
    ]
  }
}
