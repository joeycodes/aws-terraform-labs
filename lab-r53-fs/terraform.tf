# ----------------------------------------------------------------------------
# Provider
# ----------------------------------------------------------------------------
terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

## Default provider
provider "aws" {
  region = "ca-central-1"
}

provider "aws" {
  alias  = "canada"
  region = "ca-central-1"
}

provider "aws" {
  alias  = "japan"
  region = "ap-northeast-1"
}

provider "aws" {
  alias  = "europe"
  region = "eu-central-1"
}