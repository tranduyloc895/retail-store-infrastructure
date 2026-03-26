module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.5.0"

  name = "ecommerce-vpc"
  cidr = "10.0.0.0/16" 

  azs             = ["ap-southeast-1a", "ap-southeast-1b"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]

  # Enable NAT Gateway for private subnets to access the internet
  enable_nat_gateway   = true
  single_nat_gateway   = true  
  enable_dns_hostnames = true
  enable_dns_support   = true

  # EKS Subnet Tags
  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1" 
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1" 
  }
}