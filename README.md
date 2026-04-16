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
  - [06-monitoring: Observability Stack](#06-monitoring-observability-stack)
- [Thu tu trien khai](#thu-tu-trien-khai)
- [Huong dan trien khai chi tiet](#huong-dan-trien-khai-chi-tiet)
- [Cau hinh Jenkins UI](#cau-hinh-jenkins-ui)
- [Cai ArgoCD Application](#cai-argocd-application)
- [Chay Pipeline CI/CD](#chay-pipeline-cicd)
- [Phase 3 — Trien khai Monitoring](#phase-3--trien-khai-monitoring)
- [Thu hep quyen Jenkins Agent (da thuc hien)](#thu-hep-quyen-jenkins-agent-da-thuc-hien)
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
- Jenkins Agent **khong co quyen kubectl vao cluster** (xem muc [Thu hep quyen Jenkins Agent](#thu-hep-quyen-jenkins-agent-da-thuc-hien))
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
├── 05-ecr/                               # Layer 5: Container Registry
│   ├── provider.tf                       #   AWS provider + S3 backend
│   ├── ecr.tf                            #   5 ECR repos + lifecycle policies
│   ├── variables.tf                      #   Input variables
│   └── outputs.tf                        #   Repository URLs, registry ID
│
└── 06-monitoring/                        # Layer 6: Observability (Helm imperative)
    ├── README.md                         #   Huong dan rieng cho module
    ├── storageclass-gp3.yaml             #   Default StorageClass (CSI-backed)
    ├── values-kube-prometheus-stack.yaml #   Prometheus + Grafana + Alertmanager config
    ├── values-loki.yaml                  #   Loki SingleBinary mode
    ├── values-promtail.yaml              #   Promtail DaemonSet (log shipper)
    └── dashboards/
        ├── apply-dashboards.ps1          #   Dong goi JSON -> ConfigMap (server-side apply)
        ├── node-exporter-full.json       #   Dashboard 1860
        ├── k8s-cluster-monitoring.json   #   Dashboard 315
        ├── logs-app-loki.json            #   Dashboard 13639
        └── k8s-views-pods.json           #   Dashboard 15760
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

#### Cluster Addons (EKS managed)

| Addon | Phien ban | Muc dich |
|-------|-----------|----------|
| `aws-ebs-csi-driver` | `most_recent` | Dynamic PVC provisioning cho stateful workload. **Bat buoc** tu K8s 1.23+ vi plugin in-tree `kubernetes.io/aws-ebs` da deprecated. |

IAM permission cho EBS CSI cap qua **IRSA (IAM Role for Service Account)** — file `irsa-ebs-csi.tf`:
- Module: `terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks`
- Role name: `${cluster_name}-ebs-csi-driver`
- Policy attach: `AmazonEBSCSIDriverPolicy` (managed by AWS)
- Service account: `kube-system:ebs-csi-controller-sa`

> **Tai sao IRSA thay vi cap quyen cho node role?** Nguyen tac least-privilege: chi pod controller CSI duoc assume role nay, khong phai toan bo workload chay tren node.

**Hau qua o layer sau:** Module `06-monitoring` tao StorageClass `gp3` voi provisioner `ebs.csi.aws.com` — PVC cua Prometheus/Loki/Grafana tu dong binding.

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

Chi co `enable_cluster_creator_admin_permissions = true` — nguoi tao cluster (IAM user/role chay Terraform) co admin access.

> **Lich su:** Truoc khi chuyen sang GitOps, Jenkins Agent IAM role duoc cap `AmazonEKSClusterAdminPolicy` qua `access_entries`. Sau khi ArgoCD dam nhan viec apply manifest, access entry nay **da bi loai bo** (xem muc [Thu hep quyen Jenkins Agent](#thu-hep-quyen-jenkins-agent-da-thuc-hien)).

#### Security Group Rule

Khong co SG rule tu Jenkins Agent SG vao EKS cluster SG.

> **Lich su:** Truoc day co rule cho phep Jenkins Agent truy cap EKS API endpoint (port 443). Rule nay **da bi loai bo** sau khi chuyen sang GitOps — Jenkins Agent khong can goi Kubernetes API nua.

**Data Sources:** Module nay chi lookup VPC va private subnets tu module `01-network` thong qua tags. **Khong con cross-module dependency** voi `03-jenkins-server` — giup viec destroy/recreate don gian hon truoc day.

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

**IAM Role:** `jenkins-agent-role` — sau khi thu hep theo nguyen tac least-privilege:

| Policy | Muc dich | Trang thai |
|--------|----------|-----------|
| `AmazonSSMManagedInstanceCore` | Ansible provision qua SSM | Hien co |
| ECR policy (inline) | `GetAuthorizationToken`, `PutImage`, ... — chi cho `retail-store/*` | Hien co |
| ~~EKS policy (inline)~~ | ~~`DescribeCluster`, `ListClusters`, `sts:GetCallerIdentity`~~ | **Da loai bo** (post-GitOps) |

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
| 5 | `jenkins-agent` | Tao user `jenkins`, SSH authorized_keys, working directory |

> **Note:** Role `kubectl` **da bi loai bo** khoi play jenkins_agent sau khi chuyen sang GitOps — Agent khong con can goi `kubectl` nua. File role van ton tai tai `roles/kubectl/` de tai su dung neu can (vi du cho mot agent khac).

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

### 06-monitoring: Observability Stack

**Muc dich:** Thu thap metrics va logs tap trung tu toan cluster, hien thi qua Grafana.

**Deployment method:** Helm imperative (Option A). Se migrate sang ArgoCD GitOps (Option B) o Phase 3.2.

> Chi tiet trien khai tung buoc xem trong [`06-monitoring/README.md`](./06-monitoring/README.md). Muc nay tom luoc kien truc + quyet dinh.

#### Stack components

| Component | Chart | Version | Vai tro |
|-----------|-------|---------|---------|
| `kube-prometheus-stack` | `prometheus-community/kube-prometheus-stack` | 58.0.0 | Bundle: Prometheus + Alertmanager + Grafana + node-exporter + kube-state-metrics + Prometheus Operator CRDs |
| `loki` | `grafana/loki` | 6.6.0 | Log aggregation (SingleBinary mode, filesystem storage) |
| `promtail` | `grafana/promtail` | 6.16.0 | Log shipper (DaemonSet, tail `/var/log/pods/*`) |

#### Pham vi giam sat

| Lop | Thu thap gi |
|-----|-------------|
| **System** (node-exporter) | CPU/RAM/Disk/Network tung EKS worker node |
| **Platform** (kube-state-metrics + kubelet) | Trang thai pod/deployment/PVC, restart, OOMKill, per-container CPU/RAM |
| **Control plane** (EKS API server) | Request rate, latency per verb |
| **Logs** (Promtail -> Loki) | Stdout/stderr MOI pod: kube-system, argocd, monitoring, retail-store |
| **Application metrics** (HTTP rate, p95, 5xx) | **CHUA co** — scope Phase 3.2 (instrumentation UI + ServiceMonitor) |

#### Resource footprint

| Resource | Config | Muc dich |
|----------|--------|----------|
| Prometheus PVC | 20Gi gp3 | TSDB, retention 15 ngay |
| Grafana PVC | 5Gi gp3 | UI config + dashboards cache |
| Alertmanager PVC | 2Gi gp3 | Silence state |
| Loki PVC | 10Gi gp3 | Log chunks, retention 7 ngay |

Tong them ~37Gi EBS gp3 / cluster (chi phi ~$4/thang).

#### Grafana access

- Mac dinh: `ClusterIP` + `kubectl port-forward svc/kps-grafana 3000:80`
- Khi demo: doi `service.type: LoadBalancer` trong values file, `helm upgrade`, lay ELB hostname
- Password admin: sinh ngau nhien qua `openssl rand`, truyen qua `--set` luc install (**khong commit**)

#### Dashboards

4 dashboard community import qua ConfigMap + Grafana sidecar pattern:

| ID | Ten | Muc dich |
|----|-----|----------|
| 1860 | Node Exporter Full | System metrics per node |
| 315 | Kubernetes Cluster Monitoring | Overview cluster |
| 13639 | Logs / App (Loki) | Log viewer realtime |
| 15760 | Kubernetes Views / Pods | Pod drill-down |

Dashboard duoc dong goi qua `apply-dashboards.ps1` dung **server-side apply** de vuot qua gioi han 256KB cua annotation `kubectl.kubernetes.io/last-applied-configuration` (dashboard 1860 ~250KB).

#### Quyet dinh thiet ke

| Quyet dinh | Ly do |
|------------|-------|
| **Helm imperative (Option A)** thay vi GitOps ngay | Tinh chinh values nhanh trong giai doan hoc; migrate sang ArgoCD khi stack on dinh |
| **Loki SingleBinary mode** (khong phai SimpleScalable) | Phu hop log <100GB/ngay, it component -> it diem loi |
| **filesystem storage** (khong phai S3) | Don gian, khong can IAM role them; scale duoc sau bang cach doi `storage.type: s3` |
| **`serviceMonitorSelectorNilUsesHelmValues: false`** | Cho phep Prometheus scrape ServiceMonitor o MOI namespace (khong phai label `release=kps`) — tien cho onboard app |
| **Tat EKS control plane components** (`kubeEtcd`, `kubeControllerManager`, `kubeScheduler`, `kubeProxy`) | EKS managed, khong expose port scrape |
| **`promtail.serviceMonitor.enabled: false`** | Workaround bug template `service-metrics.yaml` trong chart v6.16.0 |
| **StorageClass `gp3` default** thay vi `gp2` | Re hon ~20%, cho phep tuy chinh IOPS/throughput doc lap; dung CSI provisioner `ebs.csi.aws.com` |

#### Phu thuoc

- `02-cluster-eks` da chay (cluster + EBS CSI driver addon)
- Khong phu thuoc `03-jenkins-server` hay `05-ecr`

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
                      (EKS + ArgoCD + EBS CSI Addon)
                               │
                               ▼
Buoc 4:                  kubectl apply -f
                      retail-store-gitops/argocd/*.yml
                      (onboard ArgoCD Application)
                               │
                               ▼
Buoc 5 (Phase 3):        06-monitoring
                      (Helm install: kube-prometheus-stack
                       + Loki + Promtail + Dashboards)
```

**Dependency:**
- `02-cluster-eks` va `03-jenkins-server` deu phu thuoc `01-network` (can VPC + subnets)
- `04-ansible-config` can `03-jenkins-server` (can EC2 Instance ID + SSH key)
- `05-ecr` doc lap, chay bat ky luc nao
- `06-monitoring` can `02-cluster-eks` da co EBS CSI driver addon (de tao PVC)
- **Khong con cross-module dependency** `02 <-> 03` sau khi thu hep quyen Jenkins Agent (xem muc [Thu hep quyen](#thu-hep-quyen-jenkins-agent-da-thuc-hien))

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

## Phase 3 — Trien khai Monitoring

Sau khi pipeline CI/CD da chay on dinh, trien khai observability stack de thu thap metrics + logs tap trung.

### Pre-flight check

Truoc khi cai monitoring, verify cluster co du prerequisite:

```powershell
# [1] Context dung cluster
kubectl config current-context
# → Expected: arn:aws:eks:ap-southeast-1:...:cluster/ecommerce-cluster

# [2] Node Ready
kubectl get nodes
# → 2 node Ready, version v1.31.x

# [3] EBS CSI driver pod chay (quan trong)
kubectl get pods -n kube-system | Select-String "ebs-csi"
# → Phai co ebs-csi-controller-* va ebs-csi-node-*

# [4] StorageClass gp3 default
kubectl get storageclass
# → gp3 (default), provisioner = ebs.csi.aws.com
```

**Neu thieu EBS CSI driver:** module `02-cluster-eks` da co `cluster_addons` + `irsa-ebs-csi.tf`. Chay `terraform apply` trong module do.

**Neu thieu `gp3` StorageClass:**
```powershell
cd 06-monitoring
kubectl apply -f storageclass-gp3.yaml
kubectl patch storageclass gp2 -p '{\"metadata\": {\"annotations\":{\"storageclass.kubernetes.io/is-default-class\":\"false\"}}}'
```

### Cai dat

**1. Tao namespace:**
```powershell
kubectl create namespace monitoring
kubectl label namespace monitoring purpose=observability
```

**2. Them Helm repos:**
```powershell
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
```

**3. Sinh password Grafana va luu vao password manager:**
```powershell
$GRAFANA_PASSWORD = -join ((65..90) + (97..122) + (48..57) | Get-Random -Count 24 | ForEach-Object {[char]$_})
Write-Host "Grafana admin password: $GRAFANA_PASSWORD"
```

**4. Cai kube-prometheus-stack:**
```powershell
cd 06-monitoring

helm install kps prometheus-community/kube-prometheus-stack `
  --namespace monitoring `
  --version 58.0.0 `
  -f values-kube-prometheus-stack.yaml `
  --set grafana.adminPassword="$GRAFANA_PASSWORD" `
  --wait --timeout 10m
```

**5. Cai Loki + Promtail:**
```powershell
helm install loki grafana/loki `
  --namespace monitoring `
  --version 6.6.0 `
  -f values-loki.yaml `
  --wait --timeout 5m

helm install promtail grafana/promtail `
  --namespace monitoring `
  --version 6.16.0 `
  -f values-promtail.yaml `
  --wait --timeout 3m
```

**6. Import 4 dashboards:**
```powershell
cd dashboards
.\apply-dashboards.ps1
```

### Verify

```powershell
# Tat ca pod Running
kubectl -n monitoring get pods

# PVC Bound (3 cai: prometheus, alertmanager, grafana + 1 loki = 4)
kubectl -n monitoring get pvc

# 4 ConfigMap dashboards
kubectl -n monitoring get configmap -l grafana_dashboard=1

# Sidecar da load dashboards
kubectl -n monitoring logs deployment/kps-grafana -c grafana-sc-dashboard --tail=20 | Select-String "Writing"
```

### Truy cap Grafana

```powershell
kubectl -n monitoring port-forward svc/kps-grafana 3000:80
```

Browser `http://localhost:3000` — username `admin`, password tu buoc 3.

Kiem tra:
- **Connections → Data sources:** Prometheus va Loki deu "Save & test" thanh cong
- **Dashboards → Kubernetes folder:** 4 dashboards co data
- **Explore → Prometheus:** query `up` ra series
- **Explore → Loki:** query `{namespace="monitoring"}` ra logs

### Troubleshooting

| Trieu chung | Nguyen nhan | Fix |
|-------------|-------------|-----|
| Pod Prometheus Pending | PVC khong binding (thieu CSI driver) | Verify `kubectl get pods -n kube-system \| Select-String ebs-csi` |
| Pod Prometheus Pending voi "Insufficient memory" | Node t3.large 2 node khong du | Scale `node_desired_size = 3` trong `02-cluster-eks/variables.tf`, `terraform apply` |
| Promtail install fail "YAML parse error service-metrics.yaml" | Bug chart 6.16.0 voi `serviceMonitor.enabled=true` | File `values-promtail.yaml` da dat `serviceMonitor.enabled: false` |
| Dashboard import lon fail "annotations: Too long" | Dashboard JSON ~250KB vuot gioi han 256KB cua annotation client-side apply | Script `apply-dashboards.ps1` dung `kubectl apply --server-side=true --force-conflicts` |
| Grafana datasource Loki "Unable to connect" | Service name sai trong `additionalDataSources` | Verify: `kubectl exec deploy/kps-grafana -c grafana -- wget -qO- http://loki-gateway.monitoring.svc.cluster.local/loki/api/v1/labels` |
| `kubectl top` bao "Metrics API not available" | Chua cai metrics-server | `kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml` |

Chi tiet xem [`06-monitoring/README.md`](./06-monitoring/README.md#known-issues).

### Roadmap

Sau Phase 3.1 (hien tai):
- **Phase 3.2:** Migrate stack monitoring tu Helm imperative sang ArgoCD GitOps (Option B). Tao ArgoCD Application cho kps + Loki + Promtail, commit values files + dashboards vao `retail-store-gitops`.
- **Phase 3.3:** Instrument 5 microservice — expose `/metrics`, tao `ServiceMonitor` CRD, import dashboard chuyen cho app.
- **Phase 3.4:** PrometheusRule custom + Alertmanager routing Slack/Discord/Email.
- **Phase 3.5:** Distributed tracing (Tempo hoac Jaeger).

---

#### `04-ansible-config/site.yaml`
Da loai bo role `kubectl` khoi play `jenkins_agent`. Folder `roles/kubectl/` van duoc giu lai de tai su dung neu can.

### Quy trinh apply thay doi

```bash
# Buoc 1: Ansible — loai bo kubectl khoi Jenkins Agent (tuy chon)
cd 04-ansible-config
ANSIBLE_CONFIG=./ansible.cfg ansible-playbook site.yaml --limit jenkins_agent
# Luu y: role kubectl da bi xoa khoi playbook. Binary kubectl da cai truoc do
# se khong duoc go cai thu cong. Neu muon, SSH vao Agent va:
#   sudo rm /usr/local/bin/kubectl

# Buoc 2: Terraform — apply module 02 TRUOC (loai bo access entry + SG rule)
cd ../02-cluster-eks
terraform plan    # Xac nhan: xoa access_entry, policy_association, SG rule
terraform apply

# Buoc 3: Terraform — apply module 03 (loai bo agent_eks IAM policy)
cd ../03-jenkins-server
terraform plan    # Xac nhan: xoa aws_iam_role_policy.agent_eks
terraform apply
```

> **Tai sao apply module 02 truoc module 03?**
> Neu apply module 03 truoc (bo agent_eks IAM policy), Agent IAM role mat quyen `eks:DescribeCluster`. Luc do module 02 van con `access_entries` tham chieu role qua `data.aws_iam_role.jenkins_agent` — van hoat dong vi data source chi doc ARN, khong can policy. Tuy nhien lam theo thu tu 02 -> 03 giup ro rang hon: clear quyen vao cluster truoc, roi clear quyen tren role.

### Kiem tra sau khi apply

```bash
# 1. Verify Jenkins Agent KHONG the truy cap EKS API
# SSH vao Agent qua SSM, roi:
aws eks update-kubeconfig --name ecommerce-cluster --region ap-southeast-1
kubectl get nodes
# Expected: error "User is not authorized" (vi khong con access entry)

# 2. Verify Pipeline van chay thanh cong
# Trigger Jenkins build UI — tat ca 3 stage pass:
#   Build Docker Image -> Push to ECR -> Update GitOps

# 3. Verify ArgoCD van sync binh thuong
kubectl get application -n argocd retail-store-ui
# Expected: Synced / Healthy

# 4. Verify SG rule da bi xoa
aws ec2 describe-security-group-rules \
  --filters Name=group-id,Values=<eks-cluster-sg-id> \
  --query "SecurityGroupRules[?ReferencedGroupInfo.GroupId=='<jenkins-agent-sg-id>']"
# Expected: rong (khong con rule)
```

### Loi ich da dat duoc

| Khia canh | Cai thien cu the |
|-----------|------------------|
| **Blast radius** | Neu Jenkins Agent bi compromise: attacker chi push duoc image xau len ECR va commit xau len gitops repo — khong the `kubectl delete` cluster, khong the xoa workload |
| **Trust boundary** | CI (Jenkins) = ECR + Git. CD (ArgoCD) = Git + K8s. Khong co single point nam ca 2 quyen |
| **Compliance** | Pass "CI should not have admin access to runtime" (CIS Kubernetes Benchmark, OWASP CI/CD Security Top 10) |
| **Drift control** | Khong ai co the `kubectl edit` tu Agent de patch "hotfix" khong qua Git |
| **Teardown** | Khong con cross-module dependency 02 -> 03 — destroy theo thu tu nao cung duoc (hoac chay song song) |

### Rollback (neu can khoi phuc quyen)

Neu gap van de voi ArgoCD va can `kubectl` truc tiep tu Agent tam thoi:

```bash
# Revert 4 commit thu hep quyen
git log --oneline  # Tim commit "feat(security): narrow..."
git revert <commit-hash>
git push

# Apply lai
cd 03-jenkins-server && terraform apply
cd ../02-cluster-eks && terraform apply
cd ../04-ansible-config && ANSIBLE_CONFIG=./ansible.cfg ansible-playbook site.yaml
```

Tot hon: fix ArgoCD thay vi roll back. Neu ArgoCD chet, chay `kubectl apply` tu may local (nguoi tao cluster van co admin access qua `enable_cluster_creator_admin_permissions`).

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
- EKS cluster SG: khong co rule tu Jenkins Agent (da loai bo sau GitOps)
- **Khong mo port 22 ra internet** — SSH qua AWS SSM Session Manager
- NAT Gateway cho outbound traffic (apt, Docker pull, plugin download, ECR, GitHub)

### Access Management
- Jenkins Master: IAM role `jenkins-ssm-role` (chi SSM)
- Jenkins Agent: IAM role `jenkins-agent-role` (**chi SSM + ECR** — da thu hep khoi EKS quyen sau GitOps)
- ECR policy gioi han chi cho repositories `retail-store/*`
- EKS access entry: **khong co** entry nao cho Jenkins Agent (da loai bo sau GitOps)
- GitHub PAT: scope chi mot repo `retail-store-gitops`, quyen `Contents: write`
- SSH key tu sinh boi Terraform (RSA 4096-bit), luu local voi permission `0400`

### Secret Management
- Jenkins admin password **fetch truc tiep ve file** (khong hien thi trong Ansible log)
- AWS Account ID luu trong Jenkins Credentials (masked trong build log)
- GitHub PAT luu trong Jenkins Credentials (masked trong build log)
- **Grafana admin password** sinh random tai local (PowerShell `Get-Random` 24 ky tu), truyen vao Helm qua `--set grafana.adminPassword=...` — **khong commit vao Git**, khong hardcode trong `values-*.yaml`
- Cac file nhay cam da them vao `.gitignore`:
  - `*.pem`, `*.key`, `*.secret`
  - `jenkins_initial_admin_password.txt`
  - `.terraform/`, `.terraform.lock.hcl`

### Monitoring Security (Phase 3)
- **Grafana Service type = `ClusterIP`** (khong expose public) — truy cap qua `kubectl port-forward svc/kps-grafana 3000:80`
- **Prometheus + Alertmanager** cung la `ClusterIP` — debug qua port-forward, khong co endpoint public
- **Loki gateway** la `ClusterIP` — chi Grafana trong cluster goi qua DNS `loki-gateway.monitoring.svc.cluster.local`
- **EBS volumes encrypted at-rest** (StorageClass `gp3` co `parameters.encrypted: "true"`) — Prometheus TSDB + Loki chunks + Grafana DB deu duoc ma hoa
- **IRSA cho EBS CSI controller** — role `${cluster_name}-ebs-csi-driver` chi co policy `AmazonEBSCSIDriverPolicy`, scope gioi han OIDC provider cua cluster (least privilege)
- **Log scraping**: Promtail chay voi ServiceAccount co quyen `get/list/watch` tren pods trong moi namespace — **khong co quyen write** len cluster resource
- Neu demo hoi dong can expose Grafana, doi sang `LoadBalancer` **tam thoi** roi revert — tranh de ELB public 24/7

### Compliance
- Tat ca Ansible tasks dung **native modules** (khong dung shell/command) — idempotent va auditable
- Khong hardcode credentials trong code
- Jenkins su dung **signed repository** (GPG key verification)
- ECR bat **scan on push** cho moi image
- GitOps model: moi thay doi cluster deu co audit trail qua Git history
- Helm releases (`kps`, `loki`, `promtail`) pin version `--version X.Y.Z` de reproducible — tranh chart drift giua cac lan install

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

EKS Cluster SG khong con nhan traffic tu Jenkins — chi ArgoCD trong cluster pull tu Git repo qua NAT GW.

> **Lich su:** Truoc khi chuyen sang GitOps, Jenkins Agent co SG rule port 443 vao EKS cluster SG de chay `kubectl apply`. Rule nay da bi loai bo.

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

Sau khi thu hep quyen Jenkins Agent, **khong con cross-module dependency giua 02 va 03** — destroy theo thu tu nao cung duoc (hoac chay song song de tiet kiem thoi gian):

```bash
# 0. (Khuyen nghi) Go monitoring stack truoc de xoa sach PVC + EBS volumes
#    Neu bo qua, terraform destroy van xoa duoc cluster nhung co the de lai
#    EBS volume mo coi (status "available") trong AWS — tinh phi $0.08/GB/thang
helm uninstall promtail -n monitoring
helm uninstall loki     -n monitoring
helm uninstall kps      -n monitoring
kubectl -n monitoring delete pvc --all        # xoa PVC -> EBS volume tu xoa (reclaimPolicy=Delete)
kubectl delete namespace monitoring
# (Tuy chon) xoa CRDs cua Prometheus Operator neu khong con release nao dung:
#   kubectl get crd -o name | Select-String "monitoring.coreos.com" | ForEach-Object { kubectl delete $_ }

# 1. Xoa ArgoCD Applications (tranh ArgoCD co gang recreate resource da bi xoa)
kubectl delete application --all -n argocd

# 2. Xoa workload namespace
kubectl delete namespace retail-store

# 3. Destroy EKS + Jenkins song song (khong con phu thuoc lan nhau)
# Terminal 1:
cd 02-cluster-eks && terraform destroy

# Terminal 2 (song song):
cd 03-jenkins-server && terraform destroy

# 4. Sau khi ca 2 hoan tat, xoa VPC
cd ../01-network && terraform destroy

# 5. (Tuy chon) Xoa ECR — chi khi khong can nua
cd ../05-ecr && terraform destroy
```

> **Canh bao:** `terraform destroy` xoa toan bo resources. Dam bao da backup du lieu truoc khi chay.
>
> **Luu y EBS volumes (monitoring):** PVC cua Prometheus (20Gi), Loki (10Gi), Grafana (5Gi), Alertmanager (2Gi) lien ket voi EBS volume tu dong. Neu skip buoc 0 va destroy cluster truc tiep, AWS se de lai volume o trang thai `available`. Vao **AWS Console > EC2 > Volumes**, loc theo tag `Project=DevSecOps-Ecommerce` va status `available`, xoa tay de tranh phi luu tru.
>
> **Lich su:** Truoc khi thu hep quyen, module 02 tham chieu SG va IAM role cua module 03 qua data source — phai destroy 02 truoc, neu khong se gap loi `DependencyViolation` khi AWS xoa SG. Sau khi thu hep, dependency nay da bi loai bo hoan toan.

---

> *Du an mon hoc NT114 - Dai hoc Cong nghe Thong tin (UIT)*
