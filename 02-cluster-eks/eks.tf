module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = "ecommerce-cluster"
  cluster_version = "1.29"

  vpc_id     = data.aws_vpc.ecommerce.id
  subnet_ids = data.aws_subnets.private.ids

  cluster_endpoint_public_access = true

  cluster_enabled_log_types = ["api", "audit", "authenticator"]

  enable_cluster_creator_admin_permissions = true

  eks_managed_node_groups = {
    main_nodes = {
      min_size     = 2
      max_size     = 3
      desired_size = 2

      instance_types = ["t3.large"]
      capacity_type  = "ON_DEMAND"

      disk_size = 50
    }
  }
}