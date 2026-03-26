terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.95.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0.0"
    }
  }

  backend "s3" {
    bucket       = "devsecops-tfstate-23520868-23521463"
    key          = "03-jenkins-server/terraform.tfstate"
    region       = "ap-southeast-1"
    use_lockfile = true
  }
}

provider "aws" {
  region = "ap-southeast-1"
  default_tags {
    tags = { Project = "DevSecOps-Ecommerce", Environment = "Dev", ManagedBy = "Terraform" }
  }
}