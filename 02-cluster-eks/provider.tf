terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.95.0" 
    }
  }

  # Cấu hình Backend trỏ về S3 và DynamoDB để lưu trữ trạng thái và khóa
  backend "s3" {
    bucket         = "devsecops-tfstate-23520868-23521463" 
    key            = "02-cluster-eks/terraform.tfstate"
    region         = "ap-southeast-1"
    use_lockfile   = true
    encrypt        = true
  }
}

provider "aws" {
  region = "ap-southeast-1"

  # Tự động dán nhãn (Tag) cho mọi tài nguyên được tạo ra
  default_tags {
    tags = {
      Project     = "DevSecOps-Ecommerce"
      Environment = "Dev"
      ManagedBy   = "Terraform"
    }
  }
}