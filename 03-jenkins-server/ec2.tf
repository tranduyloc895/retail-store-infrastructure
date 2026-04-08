# Auto generate SSH key
resource "tls_private_key" "jenkins_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "jenkins_key" {
  key_name   = var.key_name
  public_key = tls_private_key.jenkins_key.public_key_openssh
}

# Initialize Jenkins Server EC2 Instance
resource "aws_instance" "jenkins" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  subnet_id     = data.aws_subnets.private.ids[0]

  vpc_security_group_ids = [aws_security_group.jenkins_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.jenkins.name
  key_name               = aws_key_pair.jenkins_key.key_name

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = var.root_volume_type
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
