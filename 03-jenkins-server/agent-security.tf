# ============================================================
# IAM Role cho Jenkins Agent
# Permissions: SSM + ECR (push/pull) + EKS (deploy)
# ============================================================

resource "aws_iam_role" "jenkins_agent_role" {
  name = "jenkins-agent-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

# SSM access (same as master - for Ansible provisioning)
resource "aws_iam_role_policy_attachment" "agent_ssm_core" {
  role       = aws_iam_role.jenkins_agent_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# ECR permissions - push/pull images
resource "aws_iam_role_policy" "agent_ecr" {
  name = "jenkins-agent-ecr-policy"
  role = aws_iam_role.jenkins_agent_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload"
        ]
        Resource = "arn:aws:ecr:${var.aws_region}:*:repository/retail-store/*"
      }
    ]
  })
}

# EKS permissions - deploy workloads
resource "aws_iam_role_policy" "agent_eks" {
  name = "jenkins-agent-eks-policy"
  role = aws_iam_role.jenkins_agent_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster",
          "eks:ListClusters"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "sts:GetCallerIdentity"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "jenkins_agent" {
  name = "jenkins-agent-instance-profile"
  role = aws_iam_role.jenkins_agent_role.name
}

# ============================================================
# Security Group cho Jenkins Agent
# ============================================================

resource "aws_security_group" "jenkins_agent_sg" {
  name        = "jenkins-agent-sg"
  description = "Security group for Jenkins Agent"
  vpc_id      = data.aws_vpc.ecommerce.id

  # Allow SSH from Jenkins Master (for SSH-based agent connection)
  ingress {
    description     = "SSH from Jenkins Master"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.jenkins_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
