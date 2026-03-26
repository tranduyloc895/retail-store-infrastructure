# Auto generate SSH key
resource "tls_private_key" "jenkins_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "jenkins_key" {
  key_name   = "jenkins-ansible-key"
  public_key = tls_private_key.jenkins_key.public_key_openssh
}

# 2. Initialize Jenkins Server EC2 Instance
resource "aws_instance" "jenkins" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.medium"
  subnet_id     = data.aws_subnets.private.ids[0]

  vpc_security_group_ids = [aws_security_group.jenkins_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.jenkins.name
  key_name               = aws_key_pair.jenkins_key.key_name

  root_block_device {
    volume_size = 50
    volume_type = "gp3"
  }

  tags = {
    Name = "Jenkins-Master"
  }
}

# Save private key to local file with secure permissions
resource "local_file" "private_key" {
  content         = tls_private_key.jenkins_key.private_key_pem
  filename        = "${path.module}/jenkins-ansible-key.pem"
  file_permission = "0400"
}

# Output Jenkins Server Private IP for later use
output "jenkins_private_ip" {
  description = "Private IP of Jenkins Server"
  value       = aws_instance.jenkins.private_ip
}