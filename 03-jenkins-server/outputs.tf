output "jenkins_private_ip" {
  description = "Private IP of Jenkins server"
  value       = aws_instance.jenkins.private_ip
}

output "jenkins_instance_id" {
  description = "EC2 Instance ID of Jenkins server (used for SSM and Ansible inventory)"
  value       = aws_instance.jenkins.id
}

output "jenkins_security_group_id" {
  description = "Security group ID attached to Jenkins server"
  value       = aws_security_group.jenkins_sg.id
}

output "jenkins_iam_role_arn" {
  description = "ARN of the IAM role attached to Jenkins server"
  value       = aws_iam_role.jenkins_ssm_role.arn
}

output "ssh_private_key" {
  description = "Private SSH key for Ansible (sensitive, use terraform output -raw)"
  value       = tls_private_key.jenkins_key.private_key_pem
  sensitive   = true
}
