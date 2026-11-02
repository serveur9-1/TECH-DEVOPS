terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # Majeure figée : une 6.x pourrait introduire des ruptures silencieuses.
      version = "~> 5.60"
    }
  }

  # L'état est local par défaut, ce qui suffit pour un environnement unique
  # piloté par une seule personne. À plusieurs, il faudrait le déporter sur un
  # bucket S3 avec verrouillage DynamoDB : l'état contient l'IP, les
  # identifiants de ressources et doit être partagé sans être versionné.
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
