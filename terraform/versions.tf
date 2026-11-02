terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # Majeure figée : une 6.x pourrait introduire des ruptures silencieuses.
      version = "~> 5.60"
    }
  }

  # État local : suffisant pour un environnement unique. À plusieurs, le
  # déporter sur S3 avec verrouillage DynamoDB.
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "terraform"
    }
  }
}
