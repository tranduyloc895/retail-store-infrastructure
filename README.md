# DevSecOps E-commerce Infrastructure

Infrastructure as Code (IaC) cho dự an DevSecOps E-commerce, su dung **Terraform** de provisioning ha tang AWS, **Ansible** de configuration management, va **Jenkins** lam CI/CD pipeline.

## Muc luc

- [Kien truc tong quan](#kien-truc-tong-quan)
- [Yeu cau he thong](#yeu-cau-he-thong)
- [Cau truc thu muc](#cau-truc-thu-muc)
- [Chi tiet tung module](#chi-tiet-tung-module)
  - [01-network: VPC & Networking](#01-network-vpc--networking)
  - [02-cluster-eks: Kubernetes Cluster & ArgoCD](#02-cluster-eks-kubernetes-cluster--argocd)
  - [03-jenkins-server: Jenkins Master & Agent](#03-jenkins-server-jenkins-master--agent)
  - [04-ansible-config: Configuration Management](#04-ansible-config-configuration-management)
  - [05-ecr: Elastic Container Registry](#05-ecr-elastic-container-registry)
- [Thu tu trien khai](#thu-tu-trien-khai)
- [Huong dan trien khai chi tiet](#huong-dan-trien-khai-chi-tiet)
- [Cau hinh Jenkins UI](#cau-hinh-jenkins-ui)
- [Chay Pipeline CI/CD](#chay-pipeline-cicd)
- [Quan ly Terraform State](#quan-ly-terraform-state)
- [Bao mat](#bao-mat)
- [So do mang](#so-do-mang)
- [Tagging Convention](#tagging-convention)
- [Teardown](#teardown-huy-ha-tang)

---

## Kien truc tong quan

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
                        │  │  │  Public Subnet    │  │  Public Subnet   │       │  │
                        │  │  │  10.0.101.0/24    │  │  10.0.102.0/24   │       │  │
                        │  │  │  (AZ: 1a)         │  │  (AZ: 1b)        │       │  │
                        │  │  └────────┬──────────┘  └──────────────────┘       │  │
                        │  │           │  NAT Gateway                           │  │
                        │  │  ┌────────▼──────────┐  ┌──────────────────┐       │  │
                        │  │  │  Private Subnet   │  │  Private Subnet  │       │  │
                        │  │  │  10.0.1.0/24      │  │  10.0.2.0/24     │       │  │
                        │  │  │  (AZ: 1a)         │  │  (AZ: 1b)        │       │  │
                        │  │  │                   │  │                  │       │  │
                        │  │  │  ┌──────────────┐ │  │ ┌─────────────┐ │       │  │
                        │  │  │  │Jenkins Master│ │  │ │ EKS Nodes   │ │       │  │
                        │  │  │  │ (t3.medium)  │ │  │ │ (t3.large)  │ │       │  │
                        │  │  │  └──────────────┘ │  │ │ x2-3 nodes  │ │       │  │
                        │  │  │  ┌──────────────┐ │  │ └─────────────┘ │       │  │
                        │  │  │  │Jenkins Agent │ │  │                  │       │  │
                        │  │  │  │ (t3.medium)  │ │  │                  │       │  │
                        │  │  │  └──────────────┘ │  │                  │       │  │
                        │  │  └───────────────────┘  └──────────────────┘       │  │
                        │  │                                                    │  │
                        │  │  ┌──────────────────────────────────────────────┐  │  │
                        │  │  │  EKS Cluster: ecommerce-cluster              │  │  │
                        │  │  │  Kubernetes 1.29 + ArgoCD                    │  │  │
                        │  │  └──────────────────────────────────────────────┘  │  │
                        │  │                                                    │  │
                        │  │  ┌──────────────────────────────────────────────┐  │  │
                        │  │  │  ECR: retail-store/{ui,catalog,cart,...}      │  │  │
                        │  │  └──────────────────────────────────────────────┘  │  │
                        │  └────────────────────────────────────────────────────┘  │
                        └──────────────────────────────────────────────────────────┘
```

**Luong CI/CD:**

```
Developer push code
       │
       ▼
Jenkins Master ──trigger──► Jenkins Agent
                               │
                    ┌──────────┼──────────┐
                    ▼          ▼          ▼
              Docker Build   Push ECR   Deploy EKS
                                         (kubectl apply)
                                            │
                                            ▼
                                     EKS Cluster
                                   (retail-store namespace)
```

---

## Yeu cau he thong

| Tool | Phien ban toi thieu | Muc dich |
|------|---------------------|----------|
| [Terraform](https://www.terraform.io/) | >= 1.5.0 | Infrastructure provisioning |
| [AWS CLI](https://aws.amazon.com/cli/) | v2 | Tuong tac voi AWS API |
| [Ansible](https://www.ansible.com/) | >= 2.14 | Configuration management |
| [AWS Session Manager Plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html) | Latest | SSH tunnel qua SSM |
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | >= 1.29 | Quan ly Kubernetes cluster |
| [Helm](https://helm.sh/) | >= 3.0 | Package manager cho Kubernetes |

**AWS Credentials:** Dam bao da cau hinh AWS credentials (`aws configure`) voi quyen du de tao VPC, EKS, EC2, ECR, IAM, S3.

---

## Cau truc thu muc

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
├── 02-cluster-eks/                       # Layer 2: Kubernetes
│   ├── provider.tf                       #   AWS + Kubernetes + Helm providers
│   ├── data.tf                           #   Lookup VPC, subnets, Jenkins Agent role/SG
│   ├── eks.tf                            #   EKS cluster + node groups + access entries
│   ├── argocd.tf                         #   ArgoCD Helm release
│   ├── variables.tf                      #   Input variables
│   └── outputs.tf                        #   Cluster name, endpoint, SG IDs
│
├── 03-jenkins-server/                    # Layer 3: CI/CD Server
│   ├── provider.tf                       #   AWS + TLS + Local providers
│   ├── data.tf                           #   Lookup VPC, subnets, AMI
│   ├── ec2.tf                            #   Jenkins Master EC2 + SSH key generation
│   ├── security.tf                       #   Master IAM role, instance profile, SG
│   ├── agent.tf                          #   Jenkins Agent EC2 instance
│   ├── agent-security.tf                 #   Agent IAM role (SSM+ECR+EKS), SG
│   ├── variables.tf                      #   Input variables (master + agent)
│   ├── outputs.tf                        #   IPs, instance IDs, SG IDs, IAM ARNs
│   └── connect-jenkins.ps1               #   PowerShell script mo SSM tunnel
│
├── 04-ansible-config/                    # Layer 4: Configuration Management
│   ├── ansible.cfg                       #   Ansible config (SSM ProxyCommand)
│   ├── site.yaml                         #   Master playbook (2 plays: master + agent)
│   ├── inventories/
│   │   └── dev/
│   │       └── hosts.ini                 #   Target hosts (EC2 instance IDs)
│   └── roles/
│       ├── common/tasks/main.yaml        #   APT cache update
│       ├── java/tasks/main.yaml          #   OpenJDK 17
│       ├── docker/tasks/main.yaml        #   Docker Engine + user groups
│       ├── jenkins/tasks/main.yaml       #   Jenkins install + password fetch
│       ├── awscli/tasks/main.yaml        #   AWS CLI v2
│       ├── kubectl/                      #   kubectl binary
│       │   ├── tasks/main.yaml
│       │   └── defaults/main.yaml        #     Version: 1.29.0
│       └── jenkins-agent/                #   Agent user + SSH authorized_keys
│           ├── tasks/main.yaml
│           └── defaults/main.yaml
│
└── 05-ecr/                               # Layer 5: Container Registry
    ├── provider.tf                       #   AWS provider + S3 backend
    ├── ecr.tf                            #   5 ECR repos + lifecycle policies
    ├── variables.tf                      #   Input variables
    └── outputs.tf                        #   Repository URLs, registry ID
```

---

## Chi tiet tung module

### 01-network: VPC & Networking

**Muc dich:** Tao nen tang mang cho toan bo ha tang.

**Module su dung:** [`terraform-aws-modules/vpc/aws`](https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws/) v5.5.0

| Resource | Gia tri |
|----------|---------|
| VPC Name | `ecommerce-vpc` |
| CIDR | `10.0.0.0/16` (65,536 IPs) |
| Region | `ap-southeast-1` (Singapore) |
| Availability Zones | `ap-southeast-1a`, `ap-southeast-1b` |
| Private Subnets | `10.0.1.0/24`, `10.0.2.0/24` |
| Public Subnets | `10.0.101.0/24`, `10.0.102.0/24` |
| NAT Gateway | Single (tiet kiem chi phi cho Dev) |
| DNS | Hostnames + Support enabled |

**Subnet Tags cho EKS:**
- Public subnets: `kubernetes.io/role/elb = 1` (external load balancer)
- Private subnets: `kubernetes.io/role/internal-elb = 1` (internal load balancer)

---

### 02-cluster-eks: Kubernetes Cluster & ArgoCD

**Muc dich:** Trien khai EKS cluster lam runtime, cai ArgoCD cho GitOps.

**Module su dung:** [`terraform-aws-modules/eks/aws`](https://registry.terraform.io/modules/terraform-aws-modules/eks/aws/) v20+

#### EKS Cluster

| Config | Gia tri |
|--------|---------|
| Cluster Name | `ecommerce-cluster` |
| Kubernetes Version | `1.29` |
| Endpoint | Public + Private access |
| Logging | API, Audit, Authenticator |
| Encryption | KMS cho Kubernetes secrets |
| Admin | Cluster creator co admin permissions |

#### Node Group: `main_nodes`

| Config | Gia tri |
|--------|---------|
| Instance Type | `t3.large` (2 vCPU, 8GB RAM) |
| Capacity Type | `ON_DEMAND` |
| Scaling | Min 2, Max 3, Desired 2 |
| Disk Size | 50 GB |

#### ArgoCD

| Config | Gia tri |
|--------|---------|
| Helm Chart | `argo-cd` v5.51.4 |
| Namespace | `argocd` (tu tao) |

#### EKS Access Entries

Jenkins Agent IAM role duoc cap quyen `AmazonEKSClusterAdminPolicy` de deploy workloads len cluster.

#### Security Group Rule

Cho phep Jenkins Agent truy cap EKS API endpoint (port 443) thong qua security group rule rieng.

**Data Sources:** Module nay lookup VPC, subnets, Jenkins Agent IAM role va security group tu cac module khac thong qua tags va ten — khong hardcode ID.

---

### 03-jenkins-server: Jenkins Master & Agent

**Muc dich:** Provision 2 EC2 instance trong private subnet — 1 Master (dieu phoi pipeline) va 1 Agent (thuc thi build, push, deploy).

#### Jenkins Master

| Config | Gia tri |
|--------|---------|
| AMI | Ubuntu 22.04 LTS (tu dong lay ban moi nhat) |
| Instance Type | `t3.medium` (2 vCPU, 4GB RAM) |
| Subnet | Private subnet |
| Root Volume | 50 GB gp3 |
| Name Tag | `Jenkins-Master` |

**IAM Role:** `jenkins-ssm-role`
- Policy: `AmazonSSMManagedInstanceCore`

**Security Group:** `jenkins-sg`

| Rule | Port | Source | Mo ta |
|------|------|--------|-------|
| Ingress | 8080/TCP | VPC CIDR | Jenkins UI |
| Egress | All | 0.0.0.0/0 | Outbound traffic |

> **Khong mo port 22.** Truy cap SSH qua AWS SSM Session Manager.

#### Jenkins Agent

| Config | Gia tri |
|--------|---------|
| AMI | Ubuntu 22.04 LTS |
| Instance Type | `t3.medium` |
| Subnet | Private subnet (cung VPC voi Master) |
| Root Volume | 50 GB gp3 |
| Name Tag | `Jenkins-Agent` |

**IAM Role:** `jenkins-agent-role` — quyen rong hon Master:

| Policy | Muc dich |
|--------|----------|
| `AmazonSSMManagedInstanceCore` | Ansible provision qua SSM |
| ECR policy (inline) | `GetAuthorizationToken`, `PutImage`, `InitiateLayerUpload`, ... — chi cho repos `retail-store/*` |
| EKS policy (inline) | `DescribeCluster`, `ListClusters`, `sts:GetCallerIdentity` |

**Security Group:** `jenkins-agent-sg`

| Rule | Port | Source | Mo ta |
|------|------|--------|-------|
| Ingress | 22/TCP | `jenkins-sg` (Master SG) | SSH agent connection |
| Egress | All | 0.0.0.0/0 | Outbound traffic |

#### SSH Key (dung chung Master + Agent)

| Config | Gia tri |
|--------|---------|
| Algorithm | RSA 4096-bit |
| Key Name | `jenkins-ansible-key` |
| Local Files | `jenkins-ansible-key.pem` (private) + `jenkins-ansible-key.pub` (public) |

Private key dung cho Ansible va Jenkins Master SSH vao Agent. Public key duoc copy vao Agent authorized_keys.

---

### 04-ansible-config: Configuration Management

**Muc dich:** Tu dong cai dat va cau hinh Jenkins Master + Agent.

#### Ket noi SSH qua SSM

```ini
[ssh_connection]
ssh_args = -o ProxyCommand="sh -c \"aws ssm start-session --target %h
    --document-name AWS-StartSSHSession --parameters 'portNumber=%p'\""
```

Ket noi SSH tunnel qua AWS Systems Manager, khong can mo port 22.

#### Inventory

Host duoc xac dinh bang **EC2 Instance ID** (khong phai IP), vi SSM dung instance ID. File `inventories/dev/hosts.ini` can duoc cap nhat Instance ID thuc te sau moi lan chay Terraform.

#### Playbook: 2 plays

**Play 1 — Jenkins Master:**

| # | Role | Mo ta |
|---|------|-------|
| 1 | `common` | APT cache update (3600s validity) |
| 2 | `java` | OpenJDK 17 (yeu cau cua Jenkins) |
| 3 | `docker` | Docker Engine + them user vao docker group |
| 4 | `jenkins` | Clean old repo -> GPG key 2026 -> Install -> Start -> Fetch password |

**Play 2 — Jenkins Agent:**

| # | Role | Mo ta |
|---|------|-------|
| 1 | `common` | APT cache update |
| 2 | `java` | OpenJDK 17 (yeu cau cua Jenkins agent process) |
| 3 | `docker` | Docker Engine (de build Docker images) |
| 4 | `awscli` | AWS CLI v2 (de ECR login, EKS kubeconfig) |
| 5 | `kubectl` | kubectl v1.29.0 (khop voi EKS cluster version) |
| 6 | `jenkins-agent` | Tao user `jenkins`, SSH authorized_keys, working directory |

**Cach chay:**

```bash
cd 04-ansible-config

# Chay toan bo (Master + Agent):
ANSIBLE_CONFIG=./ansible.cfg ansible-playbook site.yaml

# Chi chay cho Master:
ANSIBLE_CONFIG=./ansible.cfg ansible-playbook site.yaml --limit jenkins_master

# Chi chay cho Agent:
ANSIBLE_CONFIG=./ansible.cfg ansible-playbook site.yaml --limit jenkins_agent
```

---

### 05-ecr: Elastic Container Registry

**Muc dich:** Tao ECR repositories luu tru Docker images cho cac microservices.

#### Repositories

| Repository | Service |
|------------|---------|
| `retail-store/ui` | UI Service (Java/Spring Boot) |
| `retail-store/catalog` | Catalog Service (Go/Gin) |
| `retail-store/cart` | Cart Service (Java/Spring Boot) |
| `retail-store/orders` | Orders Service (Java/Spring Boot) |
| `retail-store/checkout` | Checkout Service (TypeScript/NestJS) |

#### Cau hinh

| Config | Gia tri |
|--------|---------|
| Image Tag Mutability | MUTABLE |
| Scan on Push | Enabled |
| Force Delete | true (tien cho lab) |

#### Lifecycle Policy (tu dong don dep)

| Rule | Mo ta |
|------|-------|
| Priority 1 | Xoa untagged images sau 1 ngay |
| Priority 2 | Giu toi da 5 images |

**Ve chi phi:** ECR tinh phi theo dung luong luu tru ($0.10/GB/thang). Repository rong = $0. Voi lifecycle policy, chi phi gan nhu bang 0. **Khong can `terraform destroy` ECR sau moi lan lab.**

---

## Thu tu trien khai

```
Buoc 1:  01-network         (VPC, Subnets, NAT GW)
            │
            ├──────────────────────────────────────┐
            ▼                                      ▼
Buoc 2:  02-cluster-eks     (song song)     03-jenkins-server
         (EKS + ArgoCD)                     (Master + Agent EC2)
            │                                      │
            ▼                                      ▼
Buoc 3:  terraform apply    (cap quyen)     04-ansible-config
         02-cluster-eks                     (Cai dat Jenkins, Docker, kubectl...)
         (access entry +
          SG rule cho Agent)
                                                   │
                                                   ▼
Buoc 4:                                     05-ecr (ECR repos)
                                            (chay bat ky luc nao, doc lap)
```

**Dependency:**
- `02-cluster-eks` va `03-jenkins-server` deu phu thuoc `01-network` (can VPC + subnets)
- `02-cluster-eks` can `03-jenkins-server` da chay truoc (de lookup Jenkins Agent IAM role + SG)
- `04-ansible-config` can `03-jenkins-server` (can EC2 Instance ID + SSH key)
- `05-ecr` doc lap, chay bat ky luc nao

---

## Huong dan trien khai chi tiet

### Buoc 1: Tao S3 Backend (chay 1 lan duy nhat)

Tao S3 bucket luu Terraform state (neu chua co):

```bash
aws s3api create-bucket \
  --bucket <ten-bucket-cua-ban> \
  --region ap-southeast-1 \
  --create-bucket-configuration LocationConstraint=ap-southeast-1

aws s3api put-bucket-encryption \
  --bucket <ten-bucket-cua-ban> \
  --server-side-encryption-configuration '{
    "Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]
  }'
```

**Kiem tra:** AWS Console > **S3** > tim bucket > tab Properties > Encryption = Enabled.

### Buoc 2: Trien khai VPC

```bash
cd 01-network
terraform init
terraform plan    # Xac nhan: 1 VPC, 4 subnets, 1 NAT GW, route tables, IGW
terraform apply   # Nhap "yes"
```

**Kiem tra AWS Console:**
- **VPC** > Your VPCs > `ecommerce-vpc` (CIDR `10.0.0.0/16`)
- **VPC** > Subnets > 4 subnets
- **VPC** > NAT Gateways > 1 NAT gateway (Status: Available)

### Buoc 3: Trien khai ECR

```bash
cd ../05-ecr
terraform init
terraform plan    # Xac nhan: 5 ECR repos + 5 lifecycle policies
terraform apply
```

Ghi lai `registry_id` tu output (= AWS Account ID, se dung khi cau hinh Jenkins).

**Kiem tra AWS Console:**
- **ECR** > Repositories > 5 repos `retail-store/*`
- Click vao repo bat ky > Lifecycle Policy > 2 rules

### Buoc 4: Trien khai EKS Cluster + Jenkins Server (chay song song)

**Terminal 1 — EKS (mat 15-20 phut):**

```bash
cd ../02-cluster-eks
terraform init
terraform plan
terraform apply
```

> Luu y: Lan dau chay chua co Jenkins Agent role/SG nen bo qua access entry va SG rule. Se apply lai o buoc 6.

Sau khi xong, cau hinh kubectl:

```bash
aws eks update-kubeconfig --name ecommerce-cluster --region ap-southeast-1
kubectl get nodes          # 2 nodes Ready
kubectl get pods -n argocd # ArgoCD pods Running
```

**Kiem tra AWS Console:**
- **EKS** > Clusters > `ecommerce-cluster` > Status: Active
- Tab **Compute** > Node groups > `main_nodes` > 2 nodes

**Terminal 2 — Jenkins (song song voi EKS):**

```bash
cd ../03-jenkins-server
terraform init
terraform plan    # Xac nhan: 2 EC2, 2 SG, 2 IAM roles, 1 key pair, 2 local files
terraform apply
```

**Ghi lai tat ca outputs:**
- `jenkins_instance_id` — Master Instance ID
- `agent_instance_id` — Agent Instance ID
- `agent_private_ip` — Agent IP (dung khi cau hinh Jenkins node)

**Kiem tra AWS Console:**
- **EC2** > Instances > `Jenkins-Master` + `Jenkins-Agent` (running)
- **IAM** > Roles > `jenkins-ssm-role` + `jenkins-agent-role`

### Buoc 5: Cau hinh bang Ansible

**5.1. Copy SSH key:**

```bash
cp 03-jenkins-server/jenkins-ansible-key.pem ~/.ssh/
chmod 400 ~/.ssh/jenkins-ansible-key.pem
```

**5.2. Cap nhat inventory:**

Sua file `04-ansible-config/inventories/dev/hosts.ini` — thay Instance IDs bang gia tri thuc te tu buoc 4:

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

**5.3. Chay Ansible:**

```bash
cd 04-ansible-config
ANSIBLE_CONFIG=./ansible.cfg ansible-playbook site.yaml
```

Ket qua mong doi: tat ca tasks `ok` hoac `changed`, khong co `failed`.

### Buoc 6: Cap quyen EKS cho Jenkins Agent

Sau khi buoc 4 (03-jenkins-server) hoan tat, quay lai apply EKS de them access entry va SG rule:

```bash
cd ../02-cluster-eks
terraform plan    # Xac nhan them: access_entry, policy_association, security_group_rule
terraform apply
```

**Kiem tra AWS Console:**
- **EKS** > `ecommerce-cluster` > tab **Access** > thay `jenkins-agent-role`
- **EC2** > Security Groups > SG cua EKS cluster > Inbound rules > TCP 443 from `jenkins-agent-sg`

### Buoc 7: Mo Jenkins UI

**7.1. Tao SSM tunnel:**

Windows PowerShell:
```powershell
cd 03-jenkins-server
.\connect-jenkins.ps1
```

Hoac thu cong:
```bash
aws ssm start-session \
  --target <jenkins_instance_id> \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["8080"],"localPortNumber":["8080"]}'
```

**7.2. Truy cap:** Mo browser `http://localhost:8080`

**7.3. Unlock Jenkins:**
```bash
cat 04-ansible-config/jenkins_initial_admin_password.txt
```
Paste password > Continue > **Install suggested plugins** > Tao admin user > Save and Finish.

---

## Cau hinh Jenkins UI

Sau khi unlock Jenkins, can cau hinh them:

### Cai plugin

**Manage Jenkins** > **Plugins** > **Available plugins** > tim va cai:
- **SSH Agent** (ket noi agent qua SSH)

### Them Credentials

**Manage Jenkins** > **Credentials** > **System** > **Global credentials** > **Add Credentials:**

**Credential 1 — SSH key cho Agent:**
- Kind: **SSH Username with private key**
- ID: `jenkins-agent-ssh`
- Username: `jenkins`
- Private Key > Enter directly > paste noi dung file `jenkins-ansible-key.pem`

**Credential 2 — AWS Account ID:**
- Kind: **Secret text**
- ID: `aws-account-id`
- Secret: `<registry_id tu buoc 3>` (AWS Account ID)

### Them Agent Node

**Manage Jenkins** > **Nodes** > **New Node:**
- Node name: `agent-1`
- Type: **Permanent Agent**

Cau hinh:

| Field | Gia tri |
|-------|---------|
| Remote root directory | `/var/lib/jenkins/agent` |
| Labels | `docker-agent` |
| Usage | Use this node as much as possible |
| Launch method | Launch agents via SSH |
| Host | `<agent_private_ip>` (tu Terraform output) |
| Credentials | `jenkins-agent-ssh` |
| Host Key Verification | Non verifying |

Save > doi status chuyen thanh **Connected** (icon xanh).

---

## Chay Pipeline CI/CD

### Tao Pipeline Job

**Jenkins Dashboard** > **New Item:**
- Name: `ui-pipeline`
- Type: **Pipeline** > OK

Muc **Pipeline:**
- Definition: **Pipeline script from SCM**
- SCM: **Git**
- Repository URL: `<github-repo-url>`
- Branch: `*/main`
- Script Path: `src/ui/Jenkinsfile`
- Save

### Chay thu

Click **Build Now**. Pipeline chay 3 stages:

```
Build Docker Image  ──►  Push to ECR  ──►  Deploy to EKS
```

| Stage | Hanh dong |
|-------|-----------|
| Build Docker Image | Clone repo, build Docker image, tag bang commit hash |
| Push to ECR | ECR login (IAM role), push image len ECR repository |
| Deploy to EKS | `aws eks update-kubeconfig`, `kubectl apply` K8s manifests, doi rollout hoan tat |

**Ket qua mong doi:** Build SUCCESS, image xuat hien tren ECR, pods chay tren EKS.

**Kiem tra tren EKS:**
```bash
kubectl get pods -n retail-store       # 2 pods Running
kubectl get svc ui -n retail-store     # External URL (LoadBalancer)
```

Mo URL LoadBalancer tren browser de truy cap UI service.

---

## Quan ly Terraform State

Tat ca Terraform state luu tru remote tren S3 (encrypted, locking enabled).

**State keys theo module:**

| Module | State Key |
|--------|-----------|
| 01-network | `01-network/terraform.tfstate` |
| 02-cluster-eks | `02-cluster-eks/terraform.tfstate` |
| 03-jenkins-server | `03-jenkins-server/terraform.tfstate` |
| 05-ecr | `05-ecr/terraform.tfstate` |

Moi module co state file rieng, cho phep trien khai va quan ly doc lap.

---

## Bao mat

### Network Security
- Jenkins Master + Agent nam trong **private subnet** (khong co public IP)
- Jenkins Master SG: chi mo port **8080 tu VPC CIDR**
- Jenkins Agent SG: chi mo port **22 tu Jenkins Master SG**
- EKS cluster SG: chi mo port **443 tu Jenkins Agent SG**
- **Khong mo port 22 ra internet** — SSH qua AWS SSM Session Manager
- NAT Gateway cho outbound traffic (apt, Docker pull, plugin download)

### Access Management
- Jenkins Master: IAM role `jenkins-ssm-role` (chi SSM)
- Jenkins Agent: IAM role `jenkins-agent-role` (SSM + ECR + EKS — least privilege)
- ECR policy gioi han chi cho repositories `retail-store/*`
- EKS access entry cap quyen cho Jenkins Agent role
- SSH key tu sinh boi Terraform (RSA 4096-bit), luu local voi permission `0400`

### Secret Management
- Jenkins admin password **fetch truc tiep ve file** (khong hien thi trong Ansible log)
- AWS Account ID luu trong Jenkins Credentials (masked trong build log)
- Cac file nhay cam da them vao `.gitignore`:
  - `*.pem`, `*.key`, `*.secret`
  - `jenkins_initial_admin_password.txt`
  - `.terraform/`, `.terraform.lock.hcl`

### Compliance
- Tat ca Ansible tasks dung **native modules** (khong dung shell/command) — idempotent va auditable
- Khong hardcode credentials trong code
- Jenkins su dung **signed repository** (GPG key verification)
- ECR bat **scan on push** cho moi image

---

## So do mang

```
Internet
    │
    ▼
┌──────────────┐
│ Internet GW  │
└──────┬───────┘
       │
┌──────▼──────────────────────────────────────────────┐
│ Public Subnets                                       │
│ ┌─────────────────────┐  ┌─────────────────────┐    │
│ │ 10.0.101.0/24 (1a)  │  │ 10.0.102.0/24 (1b) │    │
│ │ EKS: external ELB   │  │ EKS: external ELB   │    │
│ └─────────┬───────────┘  └─────────────────────┘    │
│           │                                          │
│     ┌─────▼─────┐                                    │
│     │  NAT GW   │                                    │
│     └─────┬─────┘                                    │
└───────────┼──────────────────────────────────────────┘
            │
┌───────────▼──────────────────────────────────────────┐
│ Private Subnets                                       │
│ ┌────────────────────────┐ ┌───────────────────────┐ │
│ │ 10.0.1.0/24 (1a)       │ │ 10.0.2.0/24 (1b)     │ │
│ │                         │ │                       │ │
│ │ - Jenkins Master        │ │ - EKS Nodes           │ │
│ │   (t3.medium, port 8080)│ │   (t3.large x2-3)     │ │
│ │ - Jenkins Agent         │ │ - ArgoCD               │ │
│ │   (t3.medium, port 22)  │ │ - retail-store ns      │ │
│ │ - SSM managed           │ │                       │ │
│ └─────────────────────────┘ └───────────────────────┘ │
└───────────────────────────────────────────────────────┘
```

**Security Group Flow:**

```
Jenkins Master (jenkins-sg)
    │ port 22 (SSH)
    ▼
Jenkins Agent (jenkins-agent-sg)
    │ port 443 (HTTPS)
    ▼
EKS Cluster (eks-cluster-sg)
```

---

## Tagging Convention

Tat ca AWS resources duoc auto-tag qua Terraform provider `default_tags`:

| Tag | Gia tri | Muc dich |
|-----|---------|----------|
| `Project` | `DevSecOps-Ecommerce` | Phan loai theo du an |
| `Environment` | `Dev` | Phan loai theo moi truong |
| `ManagedBy` | `Terraform` | Xac dinh tool quan ly |

---

## Teardown (Huy ha tang)

Thuc hien **nguoc thu tu** trien khai:

```bash
# 1. Xoa workloads tren EKS truoc (tranh orphaned resources)
kubectl delete namespace retail-store

# 2. Xoa Jenkins Master + Agent
cd 03-jenkins-server && terraform destroy

# 3. Xoa EKS Cluster + ArgoCD
cd ../02-cluster-eks && terraform destroy

# 4. Xoa VPC
cd ../01-network && terraform destroy

# 5. (Tuy chon) Xoa ECR — chi khi khong can nua
cd ../05-ecr && terraform destroy
```

> **Canh bao:** `terraform destroy` xoa toan bo resources. Dam bao da backup du lieu truoc khi chay.

---

> *Du an mon hoc NT114 - Dai hoc Cong nghe Thong tin (UIT)*
