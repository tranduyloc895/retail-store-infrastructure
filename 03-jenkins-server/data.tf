# Find VPC
data "aws_vpc" "ecommerce" {
  tags = { Name = "ecommerce-vpc" }
}

# Find Private Subnets
data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.ecommerce.id]
  }
  tags = { "kubernetes.io/role/internal-elb" = "1" }
}

# Find AMI Ubuntu 22.04 LTS latest
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}