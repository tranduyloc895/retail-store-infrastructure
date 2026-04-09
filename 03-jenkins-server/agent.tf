# Jenkins Agent EC2 Instance (Build, Push, Deploy)
resource "aws_instance" "jenkins_agent" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.agent_instance_type
  subnet_id     = data.aws_subnets.private.ids[0]

  vpc_security_group_ids = [aws_security_group.jenkins_agent_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.jenkins_agent.name
  key_name               = aws_key_pair.jenkins_key.key_name

  root_block_device {
    volume_size = var.agent_root_volume_size
    volume_type = var.root_volume_type
  }

  tags = {
    Name = "Jenkins-Agent"
  }
}
