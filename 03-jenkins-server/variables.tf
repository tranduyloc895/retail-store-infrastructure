variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "ap-southeast-1"
}

variable "instance_type" {
  description = "EC2 instance type for Jenkins server"
  type        = string
  default     = "t3.medium"
}

variable "root_volume_size" {
  description = "Root EBS volume size in GB"
  type        = number
  default     = 50
}

variable "root_volume_type" {
  description = "Root EBS volume type"
  type        = string
  default     = "gp3"
}

variable "key_name" {
  description = "Name of the SSH key pair for Ansible access"
  type        = string
  default     = "jenkins-ansible-key"
}

variable "vpc_name" {
  description = "Name tag of the VPC to lookup"
  type        = string
  default     = "ecommerce-vpc"
}

variable "project" {
  description = "Project name for tagging"
  type        = string
  default     = "DevSecOps-Ecommerce"
}

variable "environment" {
  description = "Environment name (Dev, Staging, Prod)"
  type        = string
  default     = "Dev"
}
