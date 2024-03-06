terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.8"
    }
  }

  backend "s3" {
    bucket = "avm-767397974420-me-central-1-terraform-backend"
    key    = "terraform/terraform.tfstate"
    region = "me-central-1"
  }
}
