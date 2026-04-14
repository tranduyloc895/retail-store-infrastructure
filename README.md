# DevSecOps E-commerce Infrastructure

Infrastructure as Code (IaC) cho dự an DevSecOps E-commerce, su dung **Terraform** de provisioning ha tang AWS, **Ansible** de configuration management, **Jenkins** lam CI pipeline (build + push image), va **ArgoCD** lam CD pipeline (GitOps, pull-based deploy).

## Muc luc

- [Kien truc tong quan](#kien-truc-tong-quan)
- [Luong CI/CD theo mo hinh GitOps](#luong-cicd-theo-mo-hinh-gitops)
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
- [Cai ArgoCD Application](#cai-argocd-application)
- [Chay Pipeline CI/CD](#chay-pipeline-cicd)
- [Thu hep quyen Jenkins Agent (post-GitOps)](#thu-hep-quyen-jenkins-agent-post-gitops)
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
                        │  │  │  Kubernetes 1.31 + ArgoCD (GitOps)           │  │  │
                        │  │  └──────────────────────────────────────────────┘  │  │
                        │  │                                                    │  │
                        │  │  ┌──────────────────────────────────────────────┐  │  │
                        │  │  │  ECR: retail-store/{ui,catalog,cart,...}      │  │  │
                        │  │  └──────────────────────────────────────────────┘  │  │
                        │  └────────────────────────────────────────────────────┘  │
                        └──────────────────────────────────────────────────────────┘
```

---

## Luong CI/CD theo mo hinh GitOps

Du an ap dung **GitOps pull-based** thay vi push-based truyen thong:
- **Jenkins** chi chiu trach nhiem CI: build image + push ECR + cap nhat manifest.
- **ArgoCD** (chay trong cluster) chiu trach nhiem CD: poll Git repo va tu apply thay doi vao cluster.

```
Developer push code (retail-store-microservices)
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
                                     Rolling update pods
```

**Diem quan trong:**
- Jenkins Agent **khong can quyen kubectl vao cluster** (xem muc [Thu hep quyen Jenkins Agent](#thu-hep-quyen-jenkins-agent-post-gitops))
- Image tag = 7 ky tu dau cua Git commit SHA -> truy vet 1-1 giua code / image / deployment
- Rollback chi can `git revert` trong repo gitops, khong phai rebuild image

**3 repo trong he sinh thai:**

| Repo | Vai tro |
|------|---------|
| `infrastructure` (this repo) | Terraform + Ansible: VPC, EKS, Jenkins, ECR, ArgoCD |
| `retail-store-microservices` | Source code 5 services + Jenkinsfile |
| `retail-store-gitops` | K8s manifests + ArgoCD Application (source of truth cho cluster) |

---

## Yeu cau he thong

| Tool | Phien ban toi thieu | Muc dich |
|------|---------------------|----------|
| [Terraform](https://www.terraform.io/) | >= 1.5.0 | Infrastructure provisioning |
| [AWS CLI](https://aws.amazon.com/cli/) | v2 | Tuong tac voi AWS API |
| [Ansible](https://www.ansible.com/) | >= 2.14 | Configuration management |
| [AWS Session Manager Plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html) | Latest | SSH tunnel qua SSM |
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | >= 1.31 | Quan ly Kubernetes cluster |
| [Helm](https://helm.sh/) | >= 3.0 | Package manager cho Kubernetes |

**AWS Credentials:** Dam bao da cau hinh AWS credentials (`aws configure`) voi quyen du de tao VPC, EKS, EC2, ECR, IAM, S3.

**GitHub account:** Can quyen tao Fine-grained Personal Access Token cho repo `retail-store-gitops`.

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
├── 02-cluster-eks/                       # Layer 2: Kubernetes + GitOps controller
│   ├── provider.tf                       #   AWS + Kubernetes + Helm providers
│   ├── data.tf                           #   Lookup VPC, subnets, Jenkins Agent role/SG
│   ├── eks.tf                            #   EKS cluster + node groups + access entries
│   ├── argocd.tf                         #   ArgoCD Helm release
│   ├── variables.tf                      #   Input variables
│   └── outputs.tf                        #   Cluster name, endpoint, SG IDs
│
├── 03-jenkins-server/                    # Layer 3: CI Server
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
│       │   └── defaults/main.yaml        #     Version: 1.31.0
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

**Muc dich:** Trien khai EKS cluster lam runtime, cai ArgoCD lam GitOps controller.

**Module su dung:** [`terraform-aws-modules/eks/aws`](https://registry.terraform.io/modules/terraform-aws-modules/eks/aws/) v20+

#### EKS Cluster

| Config | Gia tri |
|--------|---------|
| Cluster Name | `ecommerce-cluster` |
| Kubernetes Version | `1.31` |
| Endpoint | Public + Private access |
| Logging | API, Audit, Authenticator |
| Encryption | KMS cho Kubernetes secrets |
| Admin | Cluster creator co admin permissions |

> **Luu y ve version:** EKS chi cho phep upgrade 1 minor version moi lan (1.29 -> 1.30 -> 1.31). Chon version con **standard support toi thieu 12 thang** khi tao cluster moi. Kiem tra tai [EKS Kubernetes release calendar](https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html).

#### Node Group: `main_nodes`

| Config | Gia tri |
|--------|---------|
| Instance Type | `t3.large` (2 vCPU, 8GB RAM) |
| Capacity Type | `ON_DEMAND` |
| Scaling | Min 2, Max 3, Desired 2 |
| Disk Size | 50 GB |

#### ArgoCD (GitOps Controller)

| Config | Gia tri |
|--------|---------|
| Helm Chart | `argo-cd` v5.51.4 |
| Namespace | `argocd` (tu tao) |
| Vai tro | Pull manifests tu `retail-store-gitops` repo va apply vao cluster |
| Sync policy | Auto (prune + selfHeal) — cau hinh trong file `argocd/*.yml` cua gitops repo |
| Poll interval | 3 phut (mac dinh), co the rut ngan qua webhook |

ArgoCD duoc cai ngay trong layer nay vi no la thanh phan bat buoc cua cluster — neu khong co ArgoCD, khong co gi apply manifest tu Git vao cluster.

#### EKS Access Entries

Jenkins Agent IAM role duoc cap quyen `AmazonEKSClusterAdminPolicy` de deploy workloads len cluster.

> **Roadmap:** Sau khi GitOps on dinh, quyen nay se bi **thu hep** (xem muc [Thu hep quyen Jenkins Agent](#thu-hep-quyen-jenkins-agent-post-gitops)) — vi Jenkins khong con phai goi kubectl nua.

#### Security Group Rule

Cho phep Jenkins Agent truy cap EKS API endpoint (port 443). Quyen nay cung se duoc xem xet loai bo sau khi hoan tat chuyen doi GitOps.

**Data Sources:** Module nay lookup VPC, subnets, Jenkins Agent IAM role va security group tu cac module khac thong qua tags va ten — khong hardcode ID.

---

### 03-jenkins-server: Jenkins Master & Agent

**Muc dich:** Provision 2 EC2 instance trong private subnet — 1 Master (dieu phoi pipeline) va 1 Agent (thuc thi build + push + update GitOps repo).

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

**IAM Role:** `jenkins-agent-role` — hien tai co quyen:

| Policy | Muc dich | Se giu lai sau GitOps? |
|--------|----------|------------------------|
| `AmazonSSMManagedInstanceCore` | Ansible provision qua SSM | ✅ Giu |
| ECR policy (inline) | `GetAuthorizationToken`, `PutImage`, ... — chi cho `retail-store/*` | ✅ Giu |
| EKS policy (inline) | `DescribeCluster`, `ListClusters`, `sts:GetCallerIdentity` | ❌ **Se loai bo** |

**Security Group:** `jenkins-agent-sg`

| Rule | Port | Source | Mo ta |
|------|------|--------|-------|
| Ingress | 22/TCP | `jenkins-sg` (Master SG) | SSH agent connection |
| Egress | All | 0.0.0.0/0 | Outbound traffic (ECR, GitHub) |

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
| 4 | `awscli` | AWS CLI v2 (de ECR login) |
| 5 | `kubectl` | kubectl v1.31.0 — **se loai bo sau GitOps** |
| 6 | `jenkins-agent` | Tao user `jenkins`, SSH authorized_keys, working directory |

> **Note ve role `kubectl`:** Sau khi chuyen sang GitOps hoan toan, Agent khong con goi `kubectl apply` nua, nen role nay co the loai bo. Hien tai giu lai de debug va fallback neu can.

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
Buoc 2:  05-ecr             (song song)     03-jenkins-server
         (5 ECR repos)                      (Master + Agent EC2)
            │                                      │
            │                                      ▼
            │                              04-ansible-config
            │                              (Cai Jenkins, Docker, kubectl...)
            │                                      │
            │                                      │
            └──────────────────┬───────────────────┘
                               ▼
Buoc 3:                  02-cluster-eks
                      (EKS + ArgoCD + Access Entry
                       cho Jenkins Agent)
                               │
                               ▼
Buoc 4:                  kubectl apply -f
                      retail-store-gitops/argocd/*.yml
                      (onboard ArgoCD Application)
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

### Buoc 4: Trien khai Jenkins Server

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

### Buoc 5: Cau hinh Jenkins bang Ansible

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

### Buoc 6: Trien khai EKS Cluster + ArgoCD

```bash
cd ../02-cluster-eks
terraform init
terraform plan
terraform apply    # ~15-20 phut
```

Sau khi xong, cau hinh kubectl (tu may local hoac Jenkins Agent):

```bash
aws eks update-kubeconfig --name ecommerce-cluster --region ap-southeast-1
kubectl get nodes          # 2 nodes Ready
kubectl get pods -n argocd # ArgoCD pods Running
```

**Kiem tra AWS Console:**
- **EKS** > Clusters > `ecommerce-cluster` > Status: Active
- Tab **Compute** > Node groups > `main_nodes` > 2 nodes
- Tab **Access** > thay `jenkins-agent-role`

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
- **Pipeline** (thuong co san sau khi install suggested plugins)

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

**Credential 3 — GitHub PAT cho GitOps:**
- Kind: **Username with password**
- ID: `github-gitops-token`
- Username: `<GitHub username cua ban>`
- Password: `<Fine-grained PAT cho repo retail-store-gitops>`

**Quyen can thiet cua Fine-grained PAT** (nguyen tac least-privilege):

| Permission | Access | Ly do |
|-----------|--------|-------|
| Contents | Read and write | `git clone` + `git push` |
| Metadata | Read (auto) | Bat buoc cua GitHub |
| *Cac quyen khac* | — | **Khong cap** |

Repository scope: **Chi repo `retail-store-gitops`**, khong cap toan bo org/user.

**Expiration:** Nen dat 90 ngay (khong chon "No expiration") — neu token leak thi van co TTL.

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

## Cai ArgoCD Application

Sau khi EKS cluster co ArgoCD chay (Buoc 6), can dang ky Application de ArgoCD biet repo nao va folder nao can track.

**7.1. Clone repo gitops:**

```bash
git clone https://github.com/<your-username>/retail-store-gitops.git
cd retail-store-gitops
```

**7.2. Apply ArgoCD Application:**

```bash
# Dam bao kubectl da tro ve cluster
aws eks update-kubeconfig --name ecommerce-cluster --region ap-southeast-1

# Apply Application definition
kubectl apply -f argocd/ui-application.yml
```

**7.3. Kiem tra:**

```bash
kubectl get application -n argocd
# NAME              SYNC STATUS   HEALTH STATUS
# retail-store-ui   Synced        Healthy
```

**7.4. Truy cap ArgoCD UI:**

```bash
# Port-forward ArgoCD server
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Lay password admin ban dau
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath="{.data.password}" | base64 -d
```

Mo browser: `https://localhost:8080` — username `admin`, password tu command tren.

---

## Chay Pipeline CI/CD

### Tao Pipeline Job

**Jenkins Dashboard** > **New Item:**
- Name: `ui-pipeline`
- Type: **Pipeline** > OK

Muc **Pipeline:**
- Definition: **Pipeline script from SCM**
- SCM: **Git**
- Repository URL: `<URL cua repo retail-store-microservices>`
- Credentials: (them neu repo private)
- Branch: `*/main`
- Script Path: `src/ui/Jenkinsfile`
- Save

### Chay thu

Click **Build Now**. Pipeline chay 3 stages:

```
Build Docker Image  ──►  Push to ECR  ──►  Update GitOps
```

| Stage | Hanh dong |
|-------|-----------|
| Build Docker Image | Clone repo, build Docker image, tag bang `git rev-parse --short=7 HEAD` |
| Push to ECR | ECR login (IAM role Agent), push image len ECR repository |
| Update GitOps | Clone repo gitops, `sed` cap nhat image tag trong `apps/ui/deployment.yml`, commit + push |

**Ket qua mong doi:**
- Build SUCCESS tren Jenkins
- Image moi xuat hien tren ECR (check tab Images cua repo)
- Commit moi xuat hien trong repo `retail-store-gitops` (author: Jenkins CI)
- ArgoCD UI chuyen app `retail-store-ui` tu `Synced` -> `OutOfSync` -> `Syncing` -> `Synced` trong 3 phut
- Pod moi duoc tao tren EKS, pod cu terminating (rolling update)

**Kiem tra tren EKS:**
```bash
kubectl get pods -n retail-store       # 2 pods Running (version moi)
kubectl get svc ui -n retail-store     # External URL (LoadBalancer)
```

Mo URL LoadBalancer tren browser de kiem tra UI service.

### Trigger tu dong (roadmap)

Hien tai trigger thu cong. De tu dong:

**Option A — Webhook GitHub -> Jenkins:**
- Yeu cau Jenkins co URL public (ALB + HTTPS)
- Repo GitHub > Settings > Webhooks > URL `https://<jenkins>/github-webhook/`
- Pipeline: `triggers { githubPush() }`

**Option B — Polling SCM** (don gian hon, khong can expose Jenkins):
```groovy
triggers {
    pollSCM('H/5 * * * *')
}
```

---

## Thu hep quyen Jenkins Agent (post-GitOps)

Sau khi chuyen sang mo hinh GitOps, Jenkins Agent **khong con can quyen truc tiep vao EKS cluster nua** — moi viec apply manifest da do ArgoCD dam nhan. Day la co hoi de thu hep be mat tan cong theo nguyen tac **least privilege**.

### Danh sach thay doi code du kien

> **Note:** Day la roadmap, code Terraform se duoc thuc hien sau. README nay ghi lai de theo doi.

#### File `03-jenkins-server/agent-security.tf`

**Loai bo** (comment out hoac delete):

```hcl
# EKS permissions - deploy workloads
resource "aws_iam_role_policy" "agent_eks" {
  name = "jenkins-agent-eks-policy"
  # ...
}
```

#### File `02-cluster-eks/eks.tf`

**Loai bo** tu module `eks`:

```hcl
# Grant Jenkins Agent IAM role access to deploy workloads
access_entries = {
  jenkins_agent = {
    principal_arn = data.aws_iam_role.jenkins_agent.arn
    policy_associations = {
      cluster_admin = {
        policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
        # ...
      }
    }
  }
}
```

**Loai bo** resource:

```hcl
resource "aws_security_group_rule" "jenkins_agent_to_eks" {
  # ...
}
```

#### File `02-cluster-eks/data.tf`

**Loai bo** data source khong con can:

```hcl
data "aws_iam_role" "jenkins_agent" { ... }
data "aws_security_group" "jenkins_agent" { ... }
```

#### File `04-ansible-config/site.yaml` (tuy chon)

**Loai bo** role `kubectl` khoi play `jenkins_agent` neu khong can debug:

```yaml
- hosts: jenkins_agent
  roles:
    - common
    - java
    - docker
    - awscli
    # - kubectl        # <-- loai bo
    - jenkins-agent
```

### Loi ich sau khi thu hep

| Khia canh | Cai thien |
|-----------|-----------|
| Blast radius neu Jenkins Agent bi compromise | Khong the `kubectl delete` cluster; chi co the push image xau len ECR |
| Audit | IAM trust boundary ro rang: CI chi cham ECR + Git, CD chi cham Git + K8s |
| Compliance | Passes "CI should not have admin access to runtime" (OWASP, CIS benchmarks) |
| Drift control | Khong the `kubectl edit` thu cong tu Agent -> moi thay doi deu qua Git |

### Thu tu thuc hien khi san sang

```
1. Xac nhan GitOps da on dinh (pipeline chay thanh cong vai lan)
   │
   ▼
2. Sua 04-ansible-config/site.yaml (bo kubectl role) — optional
   Chay lai ansible-playbook de uninstall kubectl tu Agent
   │
   ▼
3. Sua 03-jenkins-server/agent-security.tf (bo agent_eks policy)
   terraform apply   # Chi remove IAM policy
   │
   ▼
4. Sua 02-cluster-eks/eks.tf (bo access_entries va SG rule)
   Sua 02-cluster-eks/data.tf (bo data sources)
   terraform apply   # Remove access entry + SG rule
   │
   ▼
5. Verify: Jenkins Agent khong the `kubectl get nodes`
   Verify: Pipeline van chay thanh cong (chi den buoc push GitOps)
   Verify: ArgoCD van sync binh thuong
```

### Canh bao

- **Khong thuc hien neu pipeline GitOps chua chay on dinh.** Mat quyen kubectl = mat kha nang deploy thu cong neu ArgoCD co su co.
- **Lam tung buoc**, apply + verify tung thay doi. Khong destroy tat ca cung luc.
- **Backup state** Terraform truoc khi sua.

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
- EKS cluster SG: chi mo port **443 tu Jenkins Agent SG** (se loai bo sau GitOps)
- **Khong mo port 22 ra internet** — SSH qua AWS SSM Session Manager
- NAT Gateway cho outbound traffic (apt, Docker pull, plugin download, ECR, GitHub)

### Access Management
- Jenkins Master: IAM role `jenkins-ssm-role` (chi SSM)
- Jenkins Agent: IAM role `jenkins-agent-role` (SSM + ECR + EKS — se thu hep xuong SSM + ECR)
- ECR policy gioi han chi cho repositories `retail-store/*`
- EKS access entry cap quyen cho Jenkins Agent role (se loai bo sau GitOps)
- GitHub PAT: scope chi mot repo `retail-store-gitops`, quyen `Contents: write`
- SSH key tu sinh boi Terraform (RSA 4096-bit), luu local voi permission `0400`

### Secret Management
- Jenkins admin password **fetch truc tiep ve file** (khong hien thi trong Ansible log)
- AWS Account ID luu trong Jenkins Credentials (masked trong build log)
- GitHub PAT luu trong Jenkins Credentials (masked trong build log)
- Cac file nhay cam da them vao `.gitignore`:
  - `*.pem`, `*.key`, `*.secret`
  - `jenkins_initial_admin_password.txt`
  - `.terraform/`, `.terraform.lock.hcl`

### Compliance
- Tat ca Ansible tasks dung **native modules** (khong dung shell/command) — idempotent va auditable
- Khong hardcode credentials trong code
- Jenkins su dung **signed repository** (GPG key verification)
- ECR bat **scan on push** cho moi image
- GitOps model: moi thay doi cluster deu co audit trail qua Git history

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

**Security Group Flow (hien tai):**

```
Jenkins Master (jenkins-sg)
    │ port 22 (SSH)
    ▼
Jenkins Agent (jenkins-agent-sg)
    │ port 443 (HTTPS) — SE LOAI BO
    ▼
EKS Cluster (eks-cluster-sg)
```

**Security Group Flow (sau khi thu hep quyen):**

```
Jenkins Master (jenkins-sg)
    │ port 22 (SSH)
    ▼
Jenkins Agent (jenkins-agent-sg)
    │ outbound only: ECR, GitHub, NAT GW
    ▼
(Internet)
```

EKS Cluster khong con nhan traffic tu Jenkins — chi ArgoCD trong cluster pull tu Git.

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

Thu tu destroy **rat quan trong** vi co cross-module dependency (02-cluster-eks tham chieu SG cua 03-jenkins-server):

```bash
# 1. Xoa ArgoCD Applications TRUOC (tranh ArgoCD co gang recreate resource da bi xoa)
kubectl delete application --all -n argocd

# 2. Xoa workload namespace
kubectl delete namespace retail-store

# 3. Xoa EKS Cluster TRUOC (vi co SG rule + access entry tham chieu jenkins-agent)
cd 02-cluster-eks && terraform destroy

# 4. Xoa Jenkins Master + Agent (SG khong con bi reference)
cd ../03-jenkins-server && terraform destroy

# 5. Xoa VPC
cd ../01-network && terraform destroy

# 6. (Tuy chon) Xoa ECR — chi khi khong can nua
cd ../05-ecr && terraform destroy
```

> **Canh bao:** `terraform destroy` xoa toan bo resources. Dam bao da backup du lieu truoc khi chay.
>
> **Neu gap loi DependencyViolation khi xoa SG:** Kiem tra xem co module nao dang tham chieu SG do khong. Destroy module tham chieu truoc.
>
> **Neu gap loi IAM role / Security Group khong tim thay khi destroy module 02 lan 2:** Data source da bi orphan. Chay `terraform state rm data.aws_iam_role.jenkins_agent` va `terraform state rm data.aws_security_group.jenkins_agent` truoc khi destroy.

---

> *Du an mon hoc NT114 - Dai hoc Cong nghe Thong tin (UIT)*
