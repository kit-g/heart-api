terraform {
  backend "s3" {
    bucket         = "922419543441-ca-central-1-tfstate"
    key            = "heart/prod/terraform.tfstate"
    region         = "ca-central-1"
    dynamodb_table = "tfstate-locks"
    encrypt        = true
  }
}
