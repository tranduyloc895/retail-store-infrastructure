# Find VPC by name tag
data "aws_vpc" "ecommerce" {
  tags = {
    Name = var.vpc_name
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

# Lookup Jenkins Agent IAM role (created by 03-jenkins-server)
data "aws_iam_role" "jenkins_agent" {
  name = "jenkins-agent-role"
}

# Lookup Jenkins Agent Security Group (created by 03-jenkins-server)
data "aws_security_group" "jenkins_agent" {
  name = "jenkins-agent-sg"
}
