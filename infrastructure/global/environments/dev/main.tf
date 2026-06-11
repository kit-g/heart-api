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
    android_sha_256 = [
      # debug
      "35:F7:BF:0F:A2:30:4C:F9:1A:52:BA:05:49:2E:07:67:53:80:BC:E9:F0:46:55:CA:2F:DE:76:79:C2:56:34:2D",
      # Play's app signing key
      "46:C5:6B:EE:A8:A0:B6:8A:A6:AD:03:FF:FF:7D:A9:28:2D:5C:D4:71:13:16:D6:FA:A8:D0:F1:26:8C:20:3D:8E",
      # upload key
      "74:AA:10:0A:FD:70:F7:65:FC:FF:70:D0:F4:9B:BE:B6:18:0A:53:68:CC:1F:61:83:05:CF:5E:65:9C:BA:AA:95",
    ]
  }
}
