# File: 02-cluster-eks/data.tf

data "aws_vpc" "ecommerce" {
  tags = {
    Name = "ecommerce-vpc"
  }
}

# Find Private Subnets in the VPC with the tag "kubernetes.io/role/internal-elb" = "1"
data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.ecommerce.id]
  }

  tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }
}