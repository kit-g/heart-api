terraform {
  backend "s3" {
    bucket         = "583168578067-us-east-2-tfstate"
    key            = "heart/dns/terraform.tfstate"
    region         = "us-east-2"
    dynamodb_table = "tfstate-locks"
    encrypt        = true
  }
}
