# DevSecOps E-commerce Infrastructure

Infrastructure as Code (IaC) cho dự án DevSecOps E-commerce, sử dụng **Terraform** để provisioning hạ tầng AWS và **Ansible** để configuration management.

## Mục lục

- [Kiến trúc tổng quan](#kiến-trúc-tổng-quan)
- [Yêu cầu hệ thống](#yêu-cầu-hệ-thống)
- [Cấu trúc thư mục](#cấu-trúc-thư-mục)
- [Chi tiết từng module](#chi-tiết-từng-module)
  - [01-network: VPC & Networking](#01-network-vpc--networking)
  - [02-cluster-eks: Kubernetes Cluster & ArgoCD](#02-cluster-eks-kubernetes-cluster--argocd)
  - [03-jenkins-server: Jenkins CI/CD Server](#03-jenkins-server-jenkins-cicd-server)
  - [04-ansible-config: Configuration Management](#04-ansible-config-configuration-management)
- [Thứ tự triển khai](#thứ-tự-triển-khai)
- [Hướng dẫn triển khai chi tiết](#hướng-dẫn-triển-khai-chi-tiết)
- [Quản lý Terraform State](#quản-lý-terraform-state)
- [Bảo mật](#bảo-mật)
- [Sơ đồ mạng](#sơ-đồ-mạng)
- [Tagging Convention](#tagging-convention)

---

## Kiến trúc tổng quan

```
                        ┌─────────────────────────────────────────────────┐
                        │                  AWS Cloud                      │
                        │              Region: ap-southeast-1             │
                        │                                                 │
                        │  ┌───────────────────────────────────────────┐  │
                        │  │         VPC: 10.0.0.0/16                  │  │
                        │  │         (ecommerce-vpc)                   │  │
                        │  │                                           │  │
                        │  │  ┌─────────────────┐ ┌─────────────────┐  │  │
                        │  │  │  Public Subnet   │ │  Public Subnet  │  │  │
                        │  │  │  10.0.101.0/24   │ │  10.0.102.0/24  │  │  │
                        │  │  │  (AZ: 1a)        │ │  (AZ: 1b)       │  │  │
                        │  │  └────────┬─────────┘ └────────┬────────┘  │  │
                        │  │           │   NAT Gateway       │          │  │
                        │  │  ┌────────▼─────────┐ ┌────────▼────────┐  │  │
                        │  │  │  Private Subnet  │ │  Private Subnet │  │  │
                        │  │  │  10.0.1.0/24     │ │  10.0.2.0/24    │  │  │
                        │  │  │  (AZ: 1a)        │ │  (AZ: 1b)       │  │  │
                        │  │  │                  │ │                 │  │  │
                        │  │  │  ┌────────────┐  │ │  ┌───────────┐ │  │  │
                        │  │  │  │  Jenkins    │  │ │  │  EKS Node │ │  │  │
                        │  │  │  │  (t3.medium)│  │ │  │  Group    │ │  │  │
                        │  │  │  └────────────┘  │ │  │(t3.large) │ │  │  │
                        │  │  │                  │ │  │  x2-3 node│ │  │  │
                        │  │  │                  │ │  └───────────┘ │  │  │
                        │  │  └──────────────────┘ └───────────────┘│  │  │
                        │  │                                           │  │
                        │  │  ┌─────────────────────────────────────┐  │  │
                        │  │  │  EKS Cluster: ecommerce-cluster     │  │  │
                        │  │  │  Kubernetes 1.29                    │  │  │
                        │  │  │  ┌──────────┐                       │  │  │
                        │  │  │  │  ArgoCD  │ (GitOps CD)           │  │  │
                        │  │  │  └──────────┘                       │  │  │
                        │  │  └─────────────────────────────────────┘  │  │
                        │  └───────────────────────────────────────────┘  │
                        └─────────────────────────────────────────────────┘
```

**Luồng CI/CD:**
1. Developer push code -> **Jenkins** (CI) build, test, scan
2. Jenkins push image -> Container Registry
3. **ArgoCD** (CD) trên EKS detect thay đổi manifest -> auto deploy lên Kubernetes

---

## Yêu cầu hệ thống

| Tool | Phiên bản tối thiểu | Mục đích |
|------|---------------------|----------|
| [Terraform](https://www.terraform.io/) | >= 1.5.0 | Infrastructure provisioning |
| [AWS CLI](https://aws.amazon.com/cli/) | v2 | Tương tác với AWS API |
| [Ansible](https://www.ansible.com/) | >= 2.14 | Configuration management |
| [AWS Session Manager Plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html) | Latest | SSH tunnel qua SSM |
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | >= 1.29 | Quản lý Kubernetes cluster |
| [Helm](https://helm.sh/) | >= 3.0 | Package manager cho Kubernetes |

**AWS Credentials:** Đảm bảo đã cấu hình AWS credentials với quyền đủ để tạo VPC, EKS, EC2, IAM, S3.

---

## Cấu trúc thư mục

```
infrastructure/
├── README.md                          # File này
├── .gitignore                         # Ignore Terraform state, secrets
│
├── 01-network/                        # Layer 1: Networking
│   ├── provider.tf                    #   AWS provider + S3 backend
│   └── vpc.tf                         #   VPC, subnets, NAT Gateway
│
├── 02-cluster-eks/                    # Layer 2: Kubernetes
│   ├── provider.tf                    #   AWS + Kubernetes + Helm providers
│   ├── data.tf                        #   Data sources (VPC, subnets lookup)
│   ├── eks.tf                         #   EKS cluster + node groups
│   └── argocd.tf                      #   ArgoCD Helm release
│
├── 03-jenkins-server/                 # Layer 3: CI/CD Server
│   ├── provider.tf                    #   AWS + TLS + Local providers
│   ├── data.tf                        #   Data sources (VPC, subnets, AMI)
│   ├── ec2.tf                         #   EC2 instance + SSH key generation
│   └── security.tf                    #   IAM role, instance profile, SG
│
└── 04-ansible-config/                 # Layer 4: Configuration Management
    ├── ansible.cfg                    #   Ansible config (SSM ProxyCommand)
    ├── site.yaml                      #   Master playbook
    ├── inventories/
    │   └── dev/
    │       └── hosts.ini              #   Target hosts (EC2 instance ID)
    └── roles/
        ├── common/tasks/main.yaml     #   APT cache update
        ├── java/tasks/main.yaml       #   OpenJDK 17 installation
        ├── docker/tasks/main.yaml     #   Docker Engine + user groups
        └── jenkins/tasks/main.yaml    #   Jenkins install + password fetch
```

---

## Chi tiết từng module

### 01-network: VPC & Networking

**Mục đích:** Tạo nền tảng mạng cho toàn bộ hạ tầng.

**Module sử dụng:** [`terraform-aws-modules/vpc/aws`](https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws/) v5.5.0

| Resource | Giá trị |
|----------|---------|
| VPC Name | `ecommerce-vpc` |
| CIDR | `10.0.0.0/16` (65,536 IPs) |
| Region | `ap-southeast-1` (Singapore) |
| Availability Zones | `ap-southeast-1a`, `ap-southeast-1b` |
| Private Subnets | `10.0.1.0/24`, `10.0.2.0/24` |
| Public Subnets | `10.0.101.0/24`, `10.0.102.0/24` |
| NAT Gateway | Single NAT Gateway (tiết kiệm chi phí cho môi trường Dev) |
| DNS | Hostnames + Support enabled |

**Subnet Tags cho EKS:**
- Public subnets: `kubernetes.io/role/elb = 1` (cho external load balancer)
- Private subnets: `kubernetes.io/role/internal-elb = 1` (cho internal load balancer)

**Terraform State Key:** `01-network/terraform.tfstate`

---

### 02-cluster-eks: Kubernetes Cluster & ArgoCD

**Mục đích:** Triển khai EKS cluster làm runtime cho ứng dụng, cài ArgoCD cho GitOps.

**Module sử dụng:** [`terraform-aws-modules/eks/aws`](https://registry.terraform.io/modules/terraform-aws-modules/eks/aws/) v20+

#### EKS Cluster

| Resource | Giá trị |
|----------|---------|
| Cluster Name | `ecommerce-cluster` |
| Kubernetes Version | `1.29` |
| Endpoint | Public access enabled |
| Logging | API, Audit, Authenticator |
| Admin Access | Cluster creator có admin permissions |

#### Node Group: `main_nodes`

| Config | Giá trị |
|--------|---------|
| Instance Type | `t3.large` (2 vCPU, 8GB RAM) |
| Capacity Type | `ON_DEMAND` |
| Min Size | 2 |
| Max Size | 3 |
| Desired Size | 2 |
| Disk Size | 50 GB (gp3) |

#### ArgoCD

| Config | Giá trị |
|--------|---------|
| Helm Chart | `argo-cd` |
| Chart Version | `5.51.4` |
| Repository | `https://argoproj.github.io/argo-helm` |
| Namespace | `argocd` (tự tạo) |

**Data Sources:** Module này lookup VPC và private subnets từ `01-network` thông qua tags (không hardcode ID), đảm bảo loose coupling giữa các layer.

**Terraform State Key:** `02-cluster-eks/terraform.tfstate`

---

### 03-jenkins-server: Jenkins CI/CD Server

**Mục đích:** Provision EC2 instance trong private subnet để chạy Jenkins.

#### EC2 Instance

| Config | Giá trị |
|--------|---------|
| AMI | Ubuntu 22.04 LTS (tự động lấy bản mới nhất) |
| Instance Type | `t3.medium` (2 vCPU, 4GB RAM) |
| Subnet | Private subnet đầu tiên |
| Root Volume | 50 GB gp3 |
| Name Tag | `Jenkins-Master` |

#### SSH Key (tự động sinh)

| Config | Giá trị |
|--------|---------|
| Algorithm | RSA 4096-bit |
| Key Name | `jenkins-ansible-key` |
| Local File | `jenkins-ansible-key.pem` (permission `0400`) |

Key này được Terraform tự sinh và lưu local, phục vụ cho Ansible kết nối SSH đến Jenkins server.

#### IAM Role & Security Group

**IAM:**
- Role: `jenkins-ssm-role` cho EC2
- Policy: `AmazonSSMManagedInstanceCore` (cho phép quản lý qua SSM)
- Instance Profile: `jenkins-instance-profile`

**Security Group: `jenkins-sg` (Zero-Trust):**

| Rule | Port | Protocol | Source | Mô tả |
|------|------|----------|--------|-------|
| Ingress | 8080 | TCP | `10.0.0.0/16` (VPC CIDR) | Jenkins UI - chỉ từ trong VPC |
| Egress | All | All | `0.0.0.0/0` | Cho phép outbound (apt, plugins...) |

> **Lưu ý:** Không mở port 22 (SSH). Truy cập SSH thông qua AWS SSM Session Manager.

**Output:** `jenkins_private_ip` - Private IP của Jenkins server để sử dụng trong Ansible inventory hoặc SSH tunnel.

**Terraform State Key:** `03-jenkins-server/terraform.tfstate`

---

### 04-ansible-config: Configuration Management

**Mục đích:** Cài đặt và cấu hình Jenkins cùng các dependency trên EC2 instance.

#### Ansible Configuration (`ansible.cfg`)

```ini
[defaults]
inventory = inventories/dev/hosts.ini
host_key_checking = False
remote_user = ubuntu

[ssh_connection]
ssh_args = -o ProxyCommand="sh -c \"aws ssm start-session --target %h --document-name AWS-StartSSHSession --parameters 'portNumber=%p'\""
```

- **remote_user:** `ubuntu` (mặc định của Ubuntu AMI)
- **SSH qua SSM:** Sử dụng `ProxyCommand` với `aws ssm start-session` để tunnel SSH qua SSM, không cần mở port 22

#### Inventory (`inventories/dev/hosts.ini`)

```ini
[jenkins_master]
i-0c371a7b09f26af8c

[jenkins_master:vars]
ansible_ssh_private_key_file=~/.ssh/jenkins-ansible-key.pem
```

- Host được xác định bằng **EC2 Instance ID** (không phải IP), vì SSM dùng instance ID
- Private key cần được copy vào `~/.ssh/` trước khi chạy

#### Roles (thực thi theo thứ tự)

| # | Role | Mô tả | Chi tiết |
|---|------|-------|----------|
| 1 | `common` | Cập nhật hệ thống | `apt update` với cache 3600s |
| 2 | `java` | Cài Java | OpenJDK 17 (yêu cầu bắt buộc của Jenkins) |
| 3 | `docker` | Cài Docker | `docker.io` + thêm user `ubuntu`, `jenkins` vào group `docker` |
| 4 | `jenkins` | Cài Jenkins | Clean old repo -> Import GPG key 2026 -> Add repo -> Install -> Start -> Fetch password |

#### Role Jenkins - Chi tiết

1. **Clean up:** Xóa old repo list và GPG key cũ (tránh conflict)
2. **GPG Key:** Download key mới từ `https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key`
3. **Repository:** Thêm Jenkins Debian stable repo (signed-by GPG key)
4. **Install & Start:** Cài Jenkins, enable systemd service
5. **Wait:** Chờ tối đa 120s cho `initialAdminPassword` được tạo (poll mỗi 5s)
6. **Fetch Password:** Download password về file local `jenkins_initial_admin_password.txt` (không hiển thị trong log Ansible - bảo mật)

---

## Thứ tự triển khai

Các module **phải** được triển khai theo thứ tự do có dependency:

```
01-network ──► 02-cluster-eks ──► 03-jenkins-server ──► 04-ansible-config
   VPC            EKS + ArgoCD      EC2 Instance          Install Jenkins
   Subnets        Node Groups       SSH Key               Java, Docker
   NAT GW         Helm releases     IAM, SG               Fetch password
```

- `02-cluster-eks` phụ thuộc vào `01-network` (cần VPC và private subnets)
- `03-jenkins-server` phụ thuộc vào `01-network` (cần VPC và private subnets)
- `04-ansible-config` phụ thuộc vào `03-jenkins-server` (cần EC2 instance ID và SSH key)

> **Ghi chú:** `02-cluster-eks` và `03-jenkins-server` có thể triển khai song song vì cả hai chỉ phụ thuộc vào `01-network`.

---

## Hướng dẫn triển khai chi tiết

### Bước 1: Triển khai VPC

```bash
cd 01-network
terraform init
terraform plan
terraform apply
```

### Bước 2: Triển khai EKS Cluster & ArgoCD

```bash
cd 02-cluster-eks
terraform init
terraform plan
terraform apply
```

Sau khi hoàn tất, cấu hình kubectl:

```bash
aws eks update-kubeconfig --name ecommerce-cluster --region ap-southeast-1
```

Kiểm tra ArgoCD:

```bash
kubectl get pods -n argocd
```

### Bước 3: Triển khai Jenkins Server

```bash
cd 03-jenkins-server
terraform init
terraform plan
terraform apply
```

Lưu output `jenkins_private_ip` để tham khảo.

### Bước 4: Cấu hình Jenkins bằng Ansible

**4.1. Copy SSH key:**

```bash
cp 03-jenkins-server/jenkins-ansible-key.pem ~/.ssh/
chmod 400 ~/.ssh/jenkins-ansible-key.pem
```

**4.2. Cập nhật Inventory:**

Sửa `04-ansible-config/inventories/dev/hosts.ini`, thay `i-0c371a7b09f26af8c` bằng Instance ID thực tế từ bước 3.

**4.3. Chạy Ansible Playbook:**

```bash
cd 04-ansible-config
ANSIBLE_CONFIG=./ansible.cfg ansible-playbook -i inventories/dev/hosts.ini site.yaml
```

**4.4. Truy cập Jenkins:**

Tạo SSM tunnel để forward port 8080:

```bash
aws ssm start-session \
  --target <instance-id> \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["8080"],"localPortNumber":["8080"]}'
```

Mở trình duyệt: `http://localhost:8080`

**4.5. Lấy mật khẩu admin:**

```bash
cat 04-ansible-config/jenkins_initial_admin_password.txt
```

Nhập mật khẩu này vào Jenkins UI để hoàn tất thiết lập.

---

## Quản lý Terraform State

Tất cả Terraform state được lưu trữ remote trên S3:

| Config | Giá trị |
|--------|---------|
| Bucket | `devsecops-tfstate-23520868-23521463` |
| Region | `ap-southeast-1` |
| Encryption | Enabled |
| Locking | Enabled (`use_lockfile = true`) |

**State keys theo module:**

| Module | State Key |
|--------|-----------|
| 01-network | `01-network/terraform.tfstate` |
| 02-cluster-eks | `02-cluster-eks/terraform.tfstate` |
| 03-jenkins-server | `03-jenkins-server/terraform.tfstate` |

Mỗi module có state file riêng biệt, cho phép triển khai và quản lý độc lập.

---

## Bảo mật

### Network Security
- Jenkins server nằm trong **private subnet** (không có public IP)
- Security group chỉ mở port **8080 từ trong VPC** (10.0.0.0/16)
- **Không mở port 22** - SSH thông qua AWS SSM Session Manager
- NAT Gateway cho phép outbound traffic (apt install, plugin download)

### Access Management
- Jenkins EC2 sử dụng **IAM Instance Profile** với policy `AmazonSSMManagedInstanceCore`
- EKS cluster creator có **admin permissions**
- SSH key được tự sinh bởi Terraform (RSA 4096-bit), lưu local với permission `0400`

### Secret Management
- Jenkins initial admin password được **fetch trực tiếp về file** (không hiển thị trong Ansible log)
- File `jenkins_initial_admin_password.txt` đã được thêm vào `.gitignore`
- SSH private key (`jenkins-ansible-key.pem`) đã được thêm vào `.gitignore`
- Terraform state được **encrypt** trên S3

### Compliance
- Tất cả Ansible tasks sử dụng **native modules** (không dùng shell/command) -> idempotent và auditable
- Không hardcode credentials trong code
- Sử dụng **signed repository** cho Jenkins (GPG key verification)

---

## Sơ đồ mạng

```
Internet
    │
    ▼
┌──────────────┐
│ Internet GW  │
└──────┬───────┘
       │
┌──────▼──────────────────────────────────────────┐
│ Public Subnets                                   │
│ ┌─────────────────────┐ ┌─────────────────────┐  │
│ │ 10.0.101.0/24 (1a)  │ │ 10.0.102.0/24 (1b) │  │
│ │ EKS: external ELB   │ │ EKS: external ELB   │  │
│ └─────────┬───────────┘ └─────────────────────┘  │
│           │                                       │
│     ┌─────▼─────┐                                 │
│     │ NAT GW    │                                 │
│     └─────┬─────┘                                 │
└───────────┼───────────────────────────────────────┘
            │
┌───────────▼───────────────────────────────────────┐
│ Private Subnets                                    │
│ ┌─────────────────────┐ ┌──────────────────────┐  │
│ │ 10.0.1.0/24 (1a)    │ │ 10.0.2.0/24 (1b)    │  │
│ │                      │ │                      │  │
│ │ - Jenkins (t3.medium)│ │ - EKS Nodes          │  │
│ │ - Port 8080 (VPC)   │ │   (t3.large x2-3)    │  │
│ │ - SSM managed       │ │ - ArgoCD              │  │
│ └──────────────────────┘ └──────────────────────┘  │
└────────────────────────────────────────────────────┘
```

---

## Tagging Convention

Tất cả AWS resources được auto-tag qua Terraform provider `default_tags`:

| Tag | Giá trị | Mục đích |
|-----|---------|----------|
| `Project` | `DevSecOps-Ecommerce` | Phân loại theo dự án |
| `Environment` | `Dev` | Phân loại theo môi trường |
| `ManagedBy` | `Terraform` | Xác định tool quản lý |

---

## Teardown (Hủy hạ tầng)

Thực hiện **ngược thứ tự** triển khai:

```bash
# 1. Xóa Jenkins Server
cd 03-jenkins-server && terraform destroy

# 2. Xóa EKS Cluster & ArgoCD
cd 02-cluster-eks && terraform destroy

# 3. Xóa VPC
cd 01-network && terraform destroy
```

> **Cảnh báo:** `terraform destroy` sẽ xóa toàn bộ resources. Đảm bảo đã backup dữ liệu cần thiết trước khi chạy.

---

> *Dự án môn học NT114 - Đại học Công nghệ Thông tin (UIT)*
