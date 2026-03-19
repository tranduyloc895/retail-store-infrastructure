terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.95.0" 
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.10.0"
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

# Lấy token xác thực tạm thời từ AWS EKS sau khi cluster được tạo xong
data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.cluster_name
}

# Cấu hình Provider cho Kubernetes
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.cluster.token
}

# Cấu hình Provider cho Helm
provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.cluster.token
  }
}
