terraform {
  backend "s3" {
    bucket         = "583168578067-ca-central-1-tfstate"
    key            = "heart/dev/terraform.tfstate"
    region         = "ca-central-1"
    dynamodb_table = "tfstate-locks"
    encrypt        = true
  }
}
