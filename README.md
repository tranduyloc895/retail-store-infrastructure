# DevSecOps E-commerce Infrastructure

Infrastructure as Code (IaC) for the DevSecOps E-commerce project. **Terraform** provisions AWS infrastructure, **Ansible** handles configuration management, **Jenkins** runs CI (build + push image), and **ArgoCD** runs CD (GitOps, pull-based deploy).

## Table of Contents

- [Overall Architecture](#overall-architecture)
- [CI/CD Flow with GitOps](#cicd-flow-with-gitops)
- [System Requirements](#system-requirements)
- [Directory Structure](#directory-structure)
- [Module Details](#module-details)
  - [01-network: VPC & Networking](#01-network-vpc--networking)
  - [02-cluster-eks: Kubernetes Cluster & ArgoCD](#02-cluster-eks-kubernetes-cluster--argocd)
  - [03-jenkins-server: Jenkins Master & Agent](#03-jenkins-server-jenkins-master--agent)
  - [04-ansible-config: Configuration Management](#04-ansible-config-configuration-management)
  - [05-ecr: Elastic Container Registry](#05-ecr-elastic-container-registry)
  - [06-monitoring: Observability Stack](#06-monitoring-observability-stack)
- [Deployment Order](#deployment-order)
- [Detailed Deployment Guide](#detailed-deployment-guide)
- [Jenkins UI Configuration](#jenkins-ui-configuration)
- [Install ArgoCD Applications](#install-argocd-applications)
- [Run the CI/CD Pipeline](#run-the-cicd-pipeline)
- [Phase 3 — Monitoring Deployment](#phase-3--monitoring-deployment)
- [Terraform State Management](#terraform-state-management)
- [Security](#security)
- [Tagging Convention](#tagging-convention)
- [Teardown (Cleanup After Each Lab)](#teardown-cleanup-after-each-lab)

---

## Overall Architecture

```
                        ┌──────────────────────────────────────────────────────────┐
                        │                      AWS Cloud                           │
                        │                 Region: ap-southeast-1                   │
                        │                                                          │
                        │  ┌────────────────────────────────────────────────────┐  │
                        │  │              VPC: 10.0.0.0/16                      │  │
                        │  │              (ecommerce-vpc)                       │  │
                        │  │                                                    │  │
                        │  │  ┌──────────────────┐  ┌──────────────────┐       │  │
                        │  │  │  Public Subnet   │  │  Public Subnet   │       │  │
                        │  │  │  10.0.101.0/24   │  │  10.0.102.0/24   │       │  │
                        │  │  │  (AZ: 1a)        │  │  (AZ: 1b)        │       │  │
                        │  │  └────────┬─────────┘  └──────────────────┘       │  │
                        │  │           │  NAT Gateway                           │  │
                        │  │  ┌────────▼─────────┐  ┌──────────────────┐       │  │
                        │  │  │  Private Subnet  │  │  Private Subnet  │       │  │
                        │  │  │  10.0.1.0/24     │  │  10.0.2.0/24     │       │  │
                        │  │  │  (AZ: 1a)        │  │  (AZ: 1b)        │       │  │
                        │  │  │                  │  │                  │       │  │
                        │  │  │ ┌──────────────┐ │  │ ┌─────────────┐  │       │  │
                        │  │  │ │Jenkins Master│ │  │ │ EKS Nodes   │  │       │  │
                        │  │  │ │ (t3.medium)  │ │  │ │ (t3.large)  │  │       │  │
                        │  │  │ └──────────────┘ │  │ │ x2-3 nodes  │  │       │  │
                        │  │  │ ┌──────────────┐ │  │ └─────────────┘  │       │  │
                        │  │  │ │Jenkins Agent │ │  │                  │       │  │
                        │  │  │ │ (t3.medium)  │ │  │                  │       │  │
                        │  │  │ └──────────────┘ │  │                  │       │  │
                        │  │  └──────────────────┘  └──────────────────┘       │  │
                        │  │                                                    │  │
                        │  │  ┌──────────────────────────────────────────────┐  │  │
                        │  │  │  EKS Cluster: ecommerce-cluster              │  │  │
                        │  │  │  Kubernetes 1.31 + ArgoCD (GitOps)           │  │  │
                        │  │  └──────────────────────────────────────────────┘  │  │
                        │  │                                                    │  │
                        │  │  ┌──────────────────────────────────────────────┐  │  │
                        │  │  │  ECR: retail-store/{ui,catalog,cart,...}     │  │  │
                        │  │  └──────────────────────────────────────────────┘  │  │
                        │  └────────────────────────────────────────────────────┘  │
                        └──────────────────────────────────────────────────────────┘
```

---

## CI/CD Flow with GitOps

The project uses **pull-based GitOps** instead of the traditional push-based model:
- **Jenkins** is responsible for CI only: build image + push to ECR + update manifest.
- **ArgoCD** (running inside the cluster) is responsible for CD: poll the Git repo and apply changes to the cluster.

```
Developer pushes code (retail-store-microservices)
        │
        ▼
Jenkins Master ──trigger──► Jenkins Agent
                               │
                    ┌──────────┼───────────┐
                    ▼          ▼           ▼
              Build Docker  Push ECR   Update GitOps Repo
                  Image                (git commit image tag)
                                            │
                                            ▼
                                      retail-store-gitops (Git)
                                            │
                            poll / webhook  │
                                            ▼
                                       ArgoCD (in-cluster)
                                            │
                                            ▼ kubectl apply
                                       EKS Cluster
                                     (retail-store ns)
                                            │
                                            ▼
                                     Rolling pod update
```

**Key design decisions:**
- Jenkins Agent has **no kubectl access to the cluster** (least-privilege CI).
- Image tag = the first 7 chars of the Git commit SHA → 1-to-1 traceability between code / image / deployment.
- Rollback only needs `git revert` in the gitops repo — no image rebuild required.

**Three repos in the ecosystem:**

| Repo | Role |
|------|------|
| `infrastructure` (this repo) | Terraform + Ansible: VPC, EKS, Jenkins, ECR |
| `retail-store-microservices` | Source code for 5 services + Jenkinsfile |
| `retail-store-gitops` | K8s manifests + ArgoCD Applications (source of truth for the cluster) |

---

## System Requirements

| Tool | Minimum version | Purpose |
|------|-----------------|---------|
| [Terraform](https://www.terraform.io/) | >= 1.5.0 | Infrastructure provisioning |
| [AWS CLI](https://aws.amazon.com/cli/) | v2 | Interact with the AWS API |
| [Ansible](https://www.ansible.com/) | >= 2.14 | Configuration management |
| [AWS Session Manager Plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html) | Latest | SSH tunnel via SSM |
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | >= 1.31 | Manage the Kubernetes cluster |
| [Helm](https://helm.sh/) | >= 3.0 | Kubernetes package manager |

**AWS Credentials:** Make sure AWS credentials are configured (`aws configure`) with sufficient permissions to create VPC, EKS, EC2, ECR, IAM, and S3 resources.

**GitHub account:** Required to create a Fine-grained Personal Access Token for the `retail-store-gitops` repo.

---

## Directory Structure

```
infrastructure/
├── README.md
├── .gitignore
│
├── 01-network/                           # Layer 1: Networking
│   ├── provider.tf                       #   AWS provider + S3 backend
│   ├── vpc.tf                            #   VPC, subnets, NAT Gateway
│   ├── variables.tf                      #   Input variables
│   └── outputs.tf                        #   VPC ID, subnet IDs, NAT IP
│
├── 02-cluster-eks/                       # Layer 2: Kubernetes + GitOps controller
│   ├── provider.tf                       #   AWS + Kubernetes + Helm providers
│   ├── data.tf                           #   Lookup VPC, subnets
│   ├── eks.tf                            #   EKS cluster + node groups + access entries
│   ├── argocd.tf                         #   ArgoCD Helm release
│   ├── irsa-ebs-csi.tf                   #   IRSA role for EBS CSI driver
│   ├── variables.tf
│   └── outputs.tf
│
├── 03-jenkins-server/                    # Layer 3: CI Server
│   ├── provider.tf
│   ├── data.tf
│   ├── ec2.tf                            #   Jenkins Master EC2 + SSH key generation
│   ├── security.tf                       #   Master IAM role, instance profile, SG
│   ├── agent.tf                          #   Jenkins Agent EC2 instance
│   ├── agent-security.tf                 #   Agent IAM role (SSM + ECR), SG
│   ├── variables.tf
│   ├── outputs.tf
│   └── connect-jenkins.ps1               #   PowerShell script to open the SSM tunnel
│
├── 04-ansible-config/                    # Layer 4: Configuration Management
│   ├── ansible.cfg                       #   Ansible config (SSM ProxyCommand)
│   ├── site.yaml                         #   Master playbook (2 plays: master + agent)
│   ├── inventories/dev/hosts.ini         #   Target hosts (EC2 instance IDs)
│   └── roles/
│       ├── common/                       #   APT cache update
│       ├── java/                         #   OpenJDK 17
│       ├── docker/                       #   Docker Engine + user groups
│       ├── jenkins/                      #   Jenkins install + password fetch
│       ├── awscli/                       #   AWS CLI v2
│       ├── kubectl/                      #   kubectl binary (kept for reuse)
│       └── jenkins-agent/                #   Agent user + SSH authorized_keys
│
├── 05-ecr/                               # Layer 5: Container Registry
│   ├── provider.tf
│   ├── ecr.tf                            #   5 ECR repos + lifecycle policies
│   ├── variables.tf
│   └── outputs.tf
│
└── 06-monitoring/                        # Layer 6: Observability — ARCHIVED (Phase 3.1 Helm scripts)
    ├── README.md                         #   Deprecation notice + migration guide
    ├── storageclass-gp3.yaml             #   (historical) Default StorageClass
    ├── values-kube-prometheus-stack.yaml #   (historical) Prometheus + Grafana + Alertmanager config
    ├── values-loki.yaml                  #   (historical) Loki SingleBinary mode
    ├── values-promtail.yaml              #   (historical) Promtail DaemonSet (log shipper)
    └── dashboards/                       #   (historical) JSON files + PowerShell apply script
```

> **Phase 3.2 note:** The monitoring stack has been migrated to GitOps. Live configuration and ArgoCD Applications now live in `retail-store-gitops/platform/monitoring/`. See [`06-monitoring/README.md`](./06-monitoring/README.md) for the full migration map.

```
```

---

## Module Details

### 01-network: VPC & Networking

**Purpose:** Build the network foundation for the entire infrastructure.

**Module used:** [`terraform-aws-modules/vpc/aws`](https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws/) v5.5.0

| Resource | Value |
|----------|-------|
| VPC Name | `ecommerce-vpc` |
| CIDR | `10.0.0.0/16` (65,536 IPs) |
| Region | `ap-southeast-1` (Singapore) |
| Availability Zones | `ap-southeast-1a`, `ap-southeast-1b` |
| Private Subnets | `10.0.1.0/24`, `10.0.2.0/24` |
| Public Subnets | `10.0.101.0/24`, `10.0.102.0/24` |
| NAT Gateway | Single (cost-saving for Dev) |
| DNS | Hostnames + Support enabled |

**Subnet Tags for EKS:**
- Public subnets: `kubernetes.io/role/elb = 1` (external load balancer)
- Private subnets: `kubernetes.io/role/internal-elb = 1` (internal load balancer)

---

### 02-cluster-eks: Kubernetes Cluster & ArgoCD

**Purpose:** Deploy the EKS cluster as the runtime and install ArgoCD as the GitOps controller.

**Module used:** [`terraform-aws-modules/eks/aws`](https://registry.terraform.io/modules/terraform-aws-modules/eks/aws/) v20+

#### EKS Cluster

| Config | Value |
|--------|-------|
| Cluster Name | `ecommerce-cluster` |
| Kubernetes Version | `1.31` |
| Endpoint | Public + Private access |
| Logging | API, Audit, Authenticator |
| Encryption | KMS for Kubernetes secrets |
| Admin | Cluster creator is granted admin permissions |

> **Version note:** EKS only allows upgrades one minor version at a time (1.29 → 1.30 → 1.31). Pick a version with **at least 12 months of standard support** when creating a new cluster. See the [EKS Kubernetes release calendar](https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html).

#### Node Group: `main_nodes`

| Config | Value |
|--------|-------|
| Instance Type | `t3.large` (2 vCPU, 8GB RAM) |
| Capacity Type | `ON_DEMAND` |
| Scaling | Min 2, Max 3, Desired 2 |
| Disk Size | 50 GB |

#### Cluster Addons (EKS managed)

| Addon | Version | Purpose |
|-------|---------|---------|
| `aws-ebs-csi-driver` | `most_recent` | Dynamic PVC provisioning for stateful workloads. **Required** since K8s 1.23+ because the in-tree `kubernetes.io/aws-ebs` plugin is deprecated. |

IAM permission for EBS CSI is granted via **IRSA (IAM Role for Service Account)** — file `irsa-ebs-csi.tf`:
- Module: `terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks`
- Role name: `${cluster_name}-ebs-csi-driver`
- Policy attached: `AmazonEBSCSIDriverPolicy` (AWS-managed)
- Service account: `kube-system:ebs-csi-controller-sa`

> **Why IRSA instead of granting permissions to the node role?** Least-privilege principle: only the CSI controller pod can assume this role, not every workload running on the node.

**Downstream effect:** The `06-monitoring` module creates a `gp3` StorageClass with provisioner `ebs.csi.aws.com` — PVCs for Prometheus / Loki / Grafana bind automatically.

#### ArgoCD (GitOps Controller)

| Config | Value |
|--------|-------|
| Helm Chart | `argo-cd` v5.51.4 |
| Namespace | `argocd` (auto-created) |
| Role | Pull manifests from the `retail-store-gitops` repo and apply to the cluster |
| Sync policy | Auto (prune + selfHeal) — configured in `argocd/*.yml` of the gitops repo |
| Poll interval | 3 minutes (default); can be reduced via webhook |

ArgoCD is installed in this layer because it is a mandatory cluster component — without ArgoCD, nothing applies manifests from Git to the cluster.

#### EKS Access Entries

Only `enable_cluster_creator_admin_permissions = true` — the cluster creator (IAM user/role running Terraform) has admin access. The Jenkins Agent has **no access entry** into the cluster (GitOps removes this need).

**Data sources:** This module only looks up the VPC and private subnets from `01-network` via tags. **No cross-module dependency** on `03-jenkins-server`, which simplifies destroy/recreate.

---

### 03-jenkins-server: Jenkins Master & Agent

**Purpose:** Provision 2 EC2 instances in private subnets — 1 Master (pipeline orchestrator) and 1 Agent (build + push + update GitOps repo).

#### Jenkins Master

| Config | Value |
|--------|-------|
| AMI | Ubuntu 22.04 LTS (auto-lookup latest) |
| Instance Type | `t3.medium` (2 vCPU, 4GB RAM) |
| Subnet | Private subnet |
| Root Volume | 50 GB gp3 |
| Name Tag | `Jenkins-Master` |

**IAM Role:** `jenkins-ssm-role`
- Policy: `AmazonSSMManagedInstanceCore`

**Security Group:** `jenkins-sg`

| Rule | Port | Source | Description |
|------|------|--------|-------------|
| Ingress | 8080/TCP | VPC CIDR | Jenkins UI |
| Egress | All | 0.0.0.0/0 | Outbound traffic |

> **Port 22 is NOT open.** SSH access goes through AWS SSM Session Manager.

#### Jenkins Agent

| Config | Value |
|--------|-------|
| AMI | Ubuntu 22.04 LTS |
| Instance Type | `t3.medium` |
| Subnet | Private subnet (same VPC as Master) |
| Root Volume | 50 GB gp3 |
| Name Tag | `Jenkins-Agent` |

**IAM Role:** `jenkins-agent-role` (least-privilege):

| Policy | Purpose |
|--------|---------|
| `AmazonSSMManagedInstanceCore` | Ansible provisioning via SSM |
| ECR policy (inline) | `GetAuthorizationToken`, `PutImage`, ... — scoped to `retail-store/*` only |

No EKS permissions — the Agent never calls the Kubernetes API (GitOps handles that).

**Security Group:** `jenkins-agent-sg`

| Rule | Port | Source | Description |
|------|------|--------|-------------|
| Ingress | 22/TCP | `jenkins-sg` (Master SG) | SSH agent connection |
| Egress | All | 0.0.0.0/0 | Outbound traffic (ECR, GitHub) |

#### SSH Key (shared Master + Agent)

| Config | Value |
|--------|-------|
| Algorithm | RSA 4096-bit |
| Key Name | `jenkins-ansible-key` |
| Local Files | `jenkins-ansible-key.pem` (private) + `jenkins-ansible-key.pub` (public) |

The private key is used by Ansible and by the Jenkins Master to SSH into the Agent. The public key is copied into the Agent's `authorized_keys`.

---

### 04-ansible-config: Configuration Management

**Purpose:** Automate installation and configuration for the Jenkins Master + Agent.

#### SSH over SSM

```ini
[ssh_connection]
ssh_args = -o ProxyCommand="sh -c \"aws ssm start-session --target %h
    --document-name AWS-StartSSHSession --parameters 'portNumber=%p'\""
```

An SSH tunnel through AWS Systems Manager — no need to expose port 22.

#### Inventory

Hosts are identified by their **EC2 Instance ID** (not IP), because SSM uses instance IDs. Update `inventories/dev/hosts.ini` with the actual Instance IDs after every Terraform run.

#### Playbook: 2 plays

**Play 1 — Jenkins Master:**

| # | Role | Description |
|---|------|-------------|
| 1 | `common` | APT cache update (3600s validity) |
| 2 | `java` | OpenJDK 17 (Jenkins requirement) |
| 3 | `docker` | Docker Engine + add user to docker group |
| 4 | `jenkins` | Clean old repo → GPG key 2026 → Install → Start → Fetch password |

**Play 2 — Jenkins Agent:**

| # | Role | Description |
|---|------|-------------|
| 1 | `common` | APT cache update |
| 2 | `java` | OpenJDK 17 (required by the Jenkins agent process) |
| 3 | `docker` | Docker Engine (to build images) |
| 4 | `awscli` | AWS CLI v2 (for ECR login) |
| 5 | `jenkins-agent` | Create `jenkins` user, SSH authorized_keys, working directory |

> **Note:** The `kubectl` role is **not** included in the Agent play — the Agent does not call the Kubernetes API under GitOps. The role files remain at `roles/kubectl/` for reuse if needed elsewhere.

**How to run:**

```bash
cd 04-ansible-config

# Run both (Master + Agent):
ANSIBLE_CONFIG=./ansible.cfg ansible-playbook site.yaml

# Master only:
ANSIBLE_CONFIG=./ansible.cfg ansible-playbook site.yaml --limit jenkins_master

# Agent only:
ANSIBLE_CONFIG=./ansible.cfg ansible-playbook site.yaml --limit jenkins_agent
```

---

### 05-ecr: Elastic Container Registry

**Purpose:** Create ECR repositories that store Docker images for the microservices.

#### Repositories

| Repository | Service |
|------------|---------|
| `retail-store/ui` | UI Service (Java/Spring Boot) |
| `retail-store/catalog` | Catalog Service (Go/Gin) |
| `retail-store/cart` | Cart Service (Java/Spring Boot) |
| `retail-store/orders` | Orders Service (Java/Spring Boot) |
| `retail-store/checkout` | Checkout Service (TypeScript/NestJS) |

#### Configuration

| Config | Value |
|--------|-------|
| Image Tag Mutability | MUTABLE |
| Scan on Push | Enabled |
| Force Delete | true (convenient for lab work) |

#### Lifecycle Policy (auto cleanup)

| Rule | Description |
|------|-------------|
| Priority 1 | Delete untagged images after 1 day |
| Priority 2 | Keep at most 5 images |

**About cost:** ECR is billed by storage usage ($0.10/GB/month). Empty repo = $0. With the lifecycle policy, the cost is close to zero. **You do not need to `terraform destroy` ECR after each lab.**

---

### 06-monitoring: Observability Stack (Archived — see GitOps repo)

**Purpose:** Collect metrics and logs cluster-wide and present them through Grafana.

**Deployment method:** ~~Helm imperative~~ → **ArgoCD GitOps** (migrated in Phase 3.2).

> The live configuration now lives in `retail-store-gitops/platform/monitoring/`. The `06-monitoring/` directory in this repo is archived for historical reference only. See [`06-monitoring/README.md`](./06-monitoring/README.md) for the full migration map.
>
> This section documents the architecture and design decisions, which are unchanged by the migration.

#### Stack components

| Component | Chart | Version | Role |
|-----------|-------|---------|------|
| `kube-prometheus-stack` | `prometheus-community/kube-prometheus-stack` | 58.0.0 | Bundle: Prometheus + Alertmanager + Grafana + node-exporter + kube-state-metrics + Prometheus Operator CRDs |
| `loki` | `grafana/loki` | 6.6.0 | Log aggregation (SingleBinary mode, filesystem storage) |
| `promtail` | `grafana/promtail` | 6.16.0 | Log shipper (DaemonSet, tails `/var/log/pods/*`) |

#### Monitoring scope

| Layer | What is collected |
|-------|-------------------|
| **System** (node-exporter) | CPU/RAM/Disk/Network per EKS worker node |
| **Platform** (kube-state-metrics + kubelet) | Pod/Deployment/PVC state, restarts, OOMKill, per-container CPU/RAM |
| **Control plane** (EKS API server) | Request rate, latency per verb |
| **Logs** (Promtail → Loki) | Stdout/stderr of ALL pods: kube-system, argocd, monitoring, retail-store |
| **Application metrics** (HTTP rate, p95, 5xx) | **NOT YET** — scoped to Phase 3.2 (UI instrumentation + ServiceMonitor) |

#### Resource footprint

| Resource | Config | Purpose |
|----------|--------|---------|
| Prometheus PVC | 20Gi gp3 | TSDB, 15-day retention |
| Grafana PVC | 5Gi gp3 | UI config + dashboards cache |
| Alertmanager PVC | 2Gi gp3 | Silence state |
| Loki PVC | 10Gi gp3 | Log chunks, 7-day retention |

Total ~37 GiB EBS gp3 per cluster (~$4/month).

#### Design decisions

| Decision | Reason |
|----------|--------|
| **Helm imperative (Option A)** instead of GitOps from day 1 | Tuning values quickly during the learning phase; migrate to ArgoCD once the stack stabilizes |
| **Loki SingleBinary mode** (not SimpleScalable) | Fits log volume <100GB/day, fewer components → fewer failure points |
| **filesystem storage** (not S3) | Simple, no extra IAM role; can later switch to `storage.type: s3` |
| **`serviceMonitorSelectorNilUsesHelmValues: false`** | Allow Prometheus to scrape ServiceMonitors in ANY namespace (not filtered by `release=kps`) — convenient for onboarding apps |
| **Disable EKS control plane components** (`kubeEtcd`, `kubeControllerManager`, `kubeScheduler`, `kubeProxy`) | EKS-managed, no scrape port exposed |
| **`promtail.serviceMonitor.enabled: false`** | Workaround for a template bug in chart v6.16.0 |
| **Default StorageClass `gp3`** instead of `gp2` | ~20% cheaper, allows independent tuning of IOPS/throughput; uses CSI provisioner `ebs.csi.aws.com` |

#### Dependencies

- `02-cluster-eks` must be applied (cluster + EBS CSI driver addon)
- Independent of `03-jenkins-server` and `05-ecr`

---

## Deployment Order

```
Step 1:  01-network         (VPC, Subnets, NAT GW)
            │
            ├──────────────────────────────────────┐
            ▼                                      ▼
Step 2:  05-ecr             (parallel)      03-jenkins-server
         (5 ECR repos)                      (Master + Agent EC2)
            │                                      │
            │                                      ▼
            │                              04-ansible-config
            │                              (Install Jenkins, Docker, ...)
            │                                      │
            │                                      │
            └──────────────────┬───────────────────┘
                               ▼
Step 3:                  02-cluster-eks
                      (EKS + ArgoCD + EBS CSI Addon)
                               │
                               ▼
Step 4:                  bash scripts/bootstrap.sh
                      (retail-store-gitops repo)
                      Creates Grafana secret + applies root Application.
                      ArgoCD syncs: 5 service apps + 6 platform monitoring apps.
                               │
                               ▼
                         All Applications Synced/Healthy
                      (monitoring up via GitOps — no manual Helm installs)
```

**Dependencies:**
- `02-cluster-eks` and `03-jenkins-server` both depend on `01-network` (need VPC + subnets)
- `04-ansible-config` depends on `03-jenkins-server` (needs EC2 Instance IDs + SSH key)
- `05-ecr` is independent — can run any time
- `06-monitoring` depends on `02-cluster-eks` having the EBS CSI driver addon (to create PVCs)
- **No cross-module dependency** between `02` and `03`

---

## Detailed Deployment Guide

### Step 1: Create the S3 Backend (one-time)

Create an S3 bucket to store Terraform state (if it does not exist):

```bash
aws s3api create-bucket \
  --bucket <your-bucket-name> \
  --region ap-southeast-1 \
  --create-bucket-configuration LocationConstraint=ap-southeast-1

aws s3api put-bucket-encryption \
  --bucket <your-bucket-name> \
  --server-side-encryption-configuration '{
    "Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]
  }'
```

**Verify:** AWS Console > **S3** > find the bucket > Properties tab > Encryption = Enabled.

### Step 2: Deploy the VPC

```bash
cd 01-network
terraform init
terraform plan    # Expect: 1 VPC, 4 subnets, 1 NAT GW, route tables, IGW
terraform apply   # Type "yes"
```

**Verify in AWS Console:**
- **VPC** > Your VPCs > `ecommerce-vpc` (CIDR `10.0.0.0/16`)
- **VPC** > Subnets > 4 subnets
- **VPC** > NAT Gateways > 1 NAT gateway (Status: Available)

### Step 3: Deploy ECR

```bash
cd ../05-ecr
terraform init
terraform plan    # Expect: 5 ECR repos + 5 lifecycle policies
terraform apply
```

Record `registry_id` from the output (= AWS Account ID, needed when configuring Jenkins).

**Verify in AWS Console:**
- **ECR** > Repositories > 5 repos `retail-store/*`
- Click any repo > Lifecycle Policy > 2 rules

### Step 4: Deploy the Jenkins Server

```bash
cd ../03-jenkins-server
terraform init
terraform plan    # Expect: 2 EC2, 2 SG, 2 IAM roles, 1 key pair, 2 local files
terraform apply
```

**Record all outputs:**
- `jenkins_instance_id` — Master Instance ID
- `agent_instance_id` — Agent Instance ID
- `agent_private_ip` — Agent IP (used when configuring the Jenkins node)

**Verify in AWS Console:**
- **EC2** > Instances > `Jenkins-Master` + `Jenkins-Agent` (running)
- **IAM** > Roles > `jenkins-ssm-role` + `jenkins-agent-role`

### Step 5: Configure Jenkins with Ansible

**5.1. Copy SSH key:**

```bash
cp 03-jenkins-server/jenkins-ansible-key.pem ~/.ssh/
chmod 400 ~/.ssh/jenkins-ansible-key.pem
```

**5.2. Update inventory:**

Edit `04-ansible-config/inventories/dev/hosts.ini` — replace Instance IDs with the actual values from Step 4:

```ini
[jenkins_master]
<jenkins_instance_id>

[jenkins_master:vars]
ansible_ssh_private_key_file=~/.ssh/jenkins-ansible-key.pem

[jenkins_agent]
<agent_instance_id>

[jenkins_agent:vars]
ansible_ssh_private_key_file=~/.ssh/jenkins-ansible-key.pem
```

**5.3. Run Ansible:**

```bash
cd 04-ansible-config
ANSIBLE_CONFIG=./ansible.cfg ansible-playbook site.yaml
```

Expected result: all tasks `ok` or `changed`, no `failed`.

### Step 6: Deploy the EKS Cluster + ArgoCD

```bash
cd ../02-cluster-eks
terraform init
terraform plan
terraform apply    # ~15-20 minutes
```

After completion, configure kubectl (from the local machine or the Jenkins Agent):

```bash
aws eks update-kubeconfig --name ecommerce-cluster --region ap-southeast-1
kubectl get nodes          # 2 nodes Ready
kubectl get pods -n argocd # ArgoCD pods Running
```

**Verify in AWS Console:**
- **EKS** > Clusters > `ecommerce-cluster` > Status: Active
- **Compute** tab > Node groups > `main_nodes` > 2 nodes
- **Access** tab > the cluster creator has admin permissions

### Step 7: Open the Jenkins UI

**7.1. Open an SSM tunnel:**

Windows PowerShell:
```powershell
cd 03-jenkins-server
.\connect-jenkins.ps1
```

Or manually:
```bash
aws ssm start-session \
  --target <jenkins_instance_id> \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["8080"],"localPortNumber":["8080"]}'
```

**7.2. Browse to:** `http://localhost:8080`

**7.3. Unlock Jenkins:**
```bash
cat 04-ansible-config/jenkins_initial_admin_password.txt
```
Paste the password > Continue > **Install suggested plugins** > create admin user > Save and Finish.

---

## Jenkins UI Configuration

After unlocking Jenkins, additional configuration is required:

### Install plugins

**Manage Jenkins** > **Plugins** > **Available plugins** > search and install:
- **SSH Agent** (to connect to the agent over SSH)
- **Pipeline** (usually already present after installing the suggested plugins)

### Add Credentials

**Manage Jenkins** > **Credentials** > **System** > **Global credentials** > **Add Credentials:**

**Credential 1 — SSH key for the Agent:**
- Kind: **SSH Username with private key**
- ID: `jenkins-agent-ssh`
- Username: `jenkins`
- Private Key > Enter directly > paste the contents of `jenkins-ansible-key.pem`

**Credential 2 — AWS Account ID:**
- Kind: **Secret text**
- ID: `aws-account-id`
- Secret: `<registry_id from Step 3>` (AWS Account ID)

**Credential 3 — GitHub PAT for GitOps:**
- Kind: **Username with password**
- ID: `github-gitops-token`
- Username: `<your GitHub username>`
- Password: `<Fine-grained PAT for the retail-store-gitops repo>`

**Required Fine-grained PAT permissions** (least-privilege):

| Permission | Access | Reason |
|-----------|--------|--------|
| Contents | Read and write | `git clone` + `git push` |
| Metadata | Read (auto) | Required by GitHub |
| *All others* | — | **Do not grant** |

Repository scope: **Only the `retail-store-gitops` repo**, not the whole org/user.

**Expiration:** Prefer 90 days (not "No expiration") — if the token leaks, it still has a TTL.

### Add an Agent Node

**Manage Jenkins** > **Nodes** > **New Node:**
- Node name: `agent-1`
- Type: **Permanent Agent**

Configuration:

| Field | Value |
|-------|-------|
| Remote root directory | `/var/lib/jenkins/agent` |
| Labels | `docker-agent` |
| Usage | Use this node as much as possible |
| Launch method | Launch agents via SSH |
| Host | `<agent_private_ip>` (from Terraform output) |
| Credentials | `jenkins-agent-ssh` |
| Host Key Verification | Non verifying |

Save > the status should switch to **Connected** (green icon).

---

## Install ArgoCD Applications

After the EKS cluster has ArgoCD running (Step 6), you need to register the Applications so ArgoCD knows which repo/folder to track.

**7.1. Clone the gitops repo:**

```bash
git clone https://github.com/<your-username>/retail-store-gitops.git
cd retail-store-gitops
```

**7.2. Apply ArgoCD Applications (all 5 services):**

```bash
# Make sure kubectl points to the cluster
aws eks update-kubeconfig --name ecommerce-cluster --region ap-southeast-1

# Apply all Application definitions
kubectl apply -f argocd/
```

**7.3. Verify:**

```bash
kubectl get application -n argocd
# NAME                    SYNC STATUS   HEALTH STATUS
# retail-store-ui         Synced        Healthy
# retail-store-catalog    Synced        Healthy
# retail-store-cart       Synced        Healthy
# retail-store-orders     Synced        Healthy
# retail-store-checkout   Synced        Healthy
```

**7.4. Access the ArgoCD UI:**

```bash
# Port-forward the ArgoCD server
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Get the initial admin password
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath="{.data.password}" | base64 -d
```

Browser: `https://localhost:8080` — username `admin`, password from the command above.

---

## Run the CI/CD Pipeline

### Create a Pipeline Job

**Jenkins Dashboard** > **New Item:**
- Name: `ui-pipeline` (or `catalog-pipeline`, `cart-pipeline`, ...)
- Type: **Pipeline** > OK

Under **Pipeline:**
- Definition: **Pipeline script from SCM**
- SCM: **Git**
- Repository URL: `<URL of retail-store-microservices repo>`
- Credentials: (add if the repo is private)
- Branch: `*/main`
- Script Path: `src/ui/Jenkinsfile` (or `src/<service>/Jenkinsfile`)
- Save

### Trigger a build

Click **Build Now**. The pipeline runs 3 stages:

```
Build Docker Image  ──►  Push to ECR  ──►  Update GitOps
```

| Stage | Action |
|-------|--------|
| Build Docker Image | Clone repo, build Docker image, tag with `git rev-parse --short=7 HEAD` |
| Push to ECR | ECR login (Agent IAM role), push image to the ECR repository |
| Update GitOps | Clone the gitops repo, `sed` the image tag in `apps/<service>/deployment.yml`, commit + push |

**Expected result:**
- Build SUCCESS in Jenkins
- New image visible in ECR (check the Images tab)
- New commit in the `retail-store-gitops` repo (author: Jenkins CI)
- ArgoCD UI transitions the app from `Synced` → `OutOfSync` → `Syncing` → `Synced` within 3 minutes
- New pods created on EKS, old pods terminating (rolling update)

**Verify on EKS:**
```bash
kubectl get pods -n retail-store       # All services Running (new version)
kubectl get svc -n retail-store        # UI has an External URL (LoadBalancer)
```

Open the LoadBalancer URL in a browser to check the UI service.

### Automatic trigger (roadmap)

Currently the trigger is manual. To automate:

**Option A — GitHub webhook → Jenkins:**
- Requires Jenkins to have a public URL (ALB + HTTPS)
- GitHub repo > Settings > Webhooks > URL `https://<jenkins>/github-webhook/`
- Pipeline: `triggers { githubPush() }`

**Option B — SCM polling** (simpler, no need to expose Jenkins):
```groovy
triggers {
    pollSCM('H/5 * * * *')
}
```

---

## Phase 3 — Monitoring Deployment (GitOps)

> **Phase 3.2 completed.** The monitoring stack is now fully managed by ArgoCD GitOps.
> The old Helm-imperative scripts in `06-monitoring/` are archived.
> **Do not run `helm install` manually** — ArgoCD owns the monitoring namespace.

The monitoring stack (Prometheus + Grafana + Loki + Promtail) is deployed automatically by `bootstrap.sh` as part of the standard cluster setup (Step 4 above).

### Pre-flight check

Before running `bootstrap.sh`, verify the cluster is ready:

```bash
# Correct cluster context
kubectl config current-context
# → arn:aws:eks:ap-southeast-1:...:cluster/ecommerce-cluster

# Nodes Ready
kubectl get nodes
# → 2 nodes Ready, version v1.31.x

# EBS CSI driver running (needed for PVCs)
kubectl get pods -n kube-system | grep ebs-csi
# → ebs-csi-controller-* and ebs-csi-node-* running

# ArgoCD running
kubectl get pods -n argocd
# → All pods Running
```

### Deploy

```bash
cd retail-store-gitops
bash scripts/bootstrap.sh
```

Save the Grafana password printed by the script. Then track sync progress:

```bash
kubectl get applications -n argocd -w
# All 12 Applications should reach Synced / Healthy within ~10 minutes.
```

### Access Grafana

```bash
kubectl -n monitoring port-forward svc/kps-grafana 3000:80
```

Browser `http://localhost:3000` — username `admin`, password from `bootstrap.sh`.

To recover a lost password:
```bash
kubectl -n monitoring get secret grafana-admin \
  -o jsonpath="{.data.admin-password}" | base64 -d
```

### Full documentation

See [`retail-store-gitops/platform/monitoring/README.md`](https://github.com/tranduyloc895/retail-store-gitops/blob/main/platform/monitoring/README.md) for:
- Architecture diagram
- Sync-wave order for the 6 ArgoCD Applications
- Dashboard list + how to add new ones
- Chart versions + upgrade procedure
- Cleanup steps

---

## Terraform State Management

All Terraform state is stored remotely on S3 (encrypted, with locking enabled).

**State keys per module:**

| Module | State Key |
|--------|-----------|
| 01-network | `01-network/terraform.tfstate` |
| 02-cluster-eks | `02-cluster-eks/terraform.tfstate` |
| 03-jenkins-server | `03-jenkins-server/terraform.tfstate` |
| 05-ecr | `05-ecr/terraform.tfstate` |

Each module has its own state file, allowing independent deployment and management.

---

## Security

### Network Security
- Jenkins Master + Agent live in **private subnets** (no public IP)
- Jenkins Master SG: only port **8080 from VPC CIDR**
- Jenkins Agent SG: only port **22 from the Jenkins Master SG**
- EKS cluster SG: no ingress from Jenkins Agent
- **Port 22 is not exposed to the internet** — SSH goes through AWS SSM Session Manager
- NAT Gateway for outbound traffic (apt, Docker pull, plugin downloads, ECR, GitHub)

### Access Management
- Jenkins Master: IAM role `jenkins-ssm-role` (SSM only)
- Jenkins Agent: IAM role `jenkins-agent-role` (**SSM + ECR only** — no EKS permissions)
- ECR policy scoped to the `retail-store/*` repositories
- EKS access entries: **none** for the Jenkins Agent
- GitHub PAT: scoped to a single repo `retail-store-gitops`, `Contents: write`
- SSH key generated by Terraform (RSA 4096-bit), stored locally with permission `0400`

### Secret Management
- Jenkins admin password **fetched directly to a file** (never printed in Ansible logs)
- AWS Account ID stored in Jenkins Credentials (masked in build logs)
- GitHub PAT stored in Jenkins Credentials (masked in build logs)
- **Grafana admin password** generated randomly locally (PowerShell `Get-Random`, 24 chars), passed via `--set grafana.adminPassword=...` — **never committed to Git**, never hard-coded in `values-*.yaml`
- Sensitive files are listed in `.gitignore`:
  - `*.pem`, `*.key`, `*.secret`
  - `jenkins_initial_admin_password.txt`
  - `.terraform/`, `.terraform.lock.hcl`

### Monitoring Security (Phase 3)
- **Grafana Service type = `ClusterIP`** (not publicly exposed) — access via `kubectl port-forward svc/kps-grafana 3000:80`
- **Prometheus + Alertmanager** are also `ClusterIP` — debug via port-forward, no public endpoint
- **Loki gateway** is `ClusterIP` — only Grafana in the cluster calls it via DNS `loki-gateway.monitoring.svc.cluster.local`
- **EBS volumes encrypted at-rest** (StorageClass `gp3` has `parameters.encrypted: "true"`) — Prometheus TSDB + Loki chunks + Grafana DB are all encrypted
- **IRSA for the EBS CSI controller** — role `${cluster_name}-ebs-csi-driver` only has `AmazonEBSCSIDriverPolicy`, scoped to the cluster's OIDC provider (least privilege)
- **Log scraping:** Promtail runs with a ServiceAccount that has `get/list/watch` on pods in every namespace — **no write permissions** to cluster resources

### Compliance
- All Ansible tasks use **native modules** (no shell/command) — idempotent and auditable
- No credentials hard-coded in code
- Jenkins uses a **signed repository** (GPG key verification)
- ECR has **scan on push** enabled for every image
- GitOps model: every cluster change has an audit trail via Git history
- Helm releases (`kps`, `loki`, `promtail`) pinned with `--version X.Y.Z` for reproducibility

---

## Tagging Convention

All AWS resources are auto-tagged via the Terraform provider `default_tags`:

| Tag | Value | Purpose |
|-----|-------|---------|
| `Project` | `DevSecOps-Ecommerce` | Classify by project |
| `Environment` | `Dev` | Classify by environment |
| `ManagedBy` | `Terraform` | Identify the managing tool |

---

## Teardown (Cleanup After Each Lab)

After narrowing Jenkins Agent permissions, **there is no cross-module dependency between `02` and `03`** — destroy in any order (or in parallel to save time).

Cleanup after each lab is strongly recommended to avoid recurring AWS charges (EKS control plane $0.10/h, NAT GW $0.045/h, EBS volumes, ELB, etc.).

```bash
# 0. (Recommended) Delete ArgoCD Applications first — this tells ArgoCD to stop
#    managing these resources, preventing it from fighting terraform destroy.
#    Also releases PVCs → EBS volumes auto-deleted (reclaimPolicy=Delete).
kubectl delete application root -n argocd          # Deletes all child Applications
kubectl delete namespace retail-store monitoring   # Removes pods, services, LoadBalancers, PVCs

# If you prefer fine-grained control (delete monitoring apps before service apps):
#   kubectl delete application platform-dashboards platform-promtail platform-loki \
#     platform-kube-prometheus-stack platform-storageclass platform-namespace -n argocd
#   kubectl delete namespace monitoring
#   kubectl delete application retail-store-ui retail-store-catalog retail-store-cart \
#     retail-store-orders retail-store-checkout -n argocd
#   kubectl delete namespace retail-store

# 3. Destroy EKS + Jenkins in parallel (no cross-module dependency anymore)
# Terminal 1:
cd 02-cluster-eks && terraform destroy

# Terminal 2 (in parallel):
cd 03-jenkins-server && terraform destroy

# 4. After both finish, delete the VPC
cd ../01-network && terraform destroy

# 5. (Optional) Delete ECR — only if you will not need it again.
#    With the lifecycle policy, ECR cost is near zero, so you can usually keep it.
cd ../05-ecr && terraform destroy
```

> **Warning:** `terraform destroy` deletes every resource. Back up data first.
>
> **Note on monitoring EBS volumes:** Prometheus (20Gi), Loki (10Gi), Grafana (5Gi), Alertmanager (2Gi) PVCs are bound to EBS volumes. If you skip Step 0 and destroy the cluster directly, AWS may leave those volumes in `available` state. Go to **AWS Console > EC2 > Volumes**, filter by tag `Project=DevSecOps-Ecommerce` and status `available`, and delete them manually to avoid storage charges.

### Quick cost-saving option (keep state)

If you only want to pause the lab (not re-run Terraform next time), keep the S3 state and ECR, but destroy compute: `02-cluster-eks` + `03-jenkins-server`. Next session, re-apply both modules to recreate the cluster and EC2 instances. The VPC and ECR stay intact.

---

> *NT114 course project — University of Information Technology (UIT)*
