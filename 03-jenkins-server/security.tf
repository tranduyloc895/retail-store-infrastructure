# IAM Role & Security Group cho Jenkins Server
resource "aws_iam_role" "jenkins_ssm_role" {
  name = "jenkins-ssm-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

# Attach policy to allow EC2 to communicate with SSM
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.jenkins_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Create Instance Profile for EC2 to use the IAM Role
resource "aws_iam_instance_profile" "jenkins" {
  name = "jenkins-instance-profile"
  role = aws_iam_role.jenkins_ssm_role.name
}

# Security Group: Firewall Zero-Trust
resource "aws_security_group" "jenkins_sg" {
  name        = "jenkins-sg"
  description = "Security group for Jenkins Server"
  vpc_id      = data.aws_vpc.ecommerce.id

  ingress {
    description = "Allow 8080 within VPC"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.ecommerce.cidr_block]
  }

  # Egress: Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
