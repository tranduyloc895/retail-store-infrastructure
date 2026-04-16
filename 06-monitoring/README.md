# 06-monitoring — Observability Stack

Trien khai stack giam sat cho EKS cluster: **Prometheus + Grafana + Loki + Promtail**.

Deployment method: **Helm imperative (Option A)**. Se migrate sang GitOps (Option B, ArgoCD manage) o Phase 3.2.

---

## Muc luc

- [Muc dich & Pham vi](#muc-dich--pham-vi)
- [Kien truc](#kien-truc)
- [Cau truc thu muc](#cau-truc-thu-muc)
- [Prerequisites](#prerequisites)
- [Trien khai](#trien-khai)
- [Truy cap Grafana](#truy-cap-grafana)
- [Dashboards](#dashboards)
- [Cac query mau](#cac-query-mau)
- [Known issues](#known-issues)
- [Teardown](#teardown)

---

## Muc dich & Pham vi

### Dang monitor gi (sau Phase 3.1)

| Lop | Component | Thu thap gi |
|-----|-----------|-------------|
| **System** | `node-exporter` (DaemonSet) | CPU/RAM/Disk/Network cua tung EKS worker node |
| **Platform** | `kube-state-metrics` | Trang thai pod/deployment/PVC, restart count, OOMKill |
| **Platform** | `kubelet / cAdvisor` (EKS built-in) | CPU/RAM per container |
| **Platform** | EKS API server | Request rate, latency per verb |
| **Self** | Prometheus, Loki, Grafana, Alertmanager | Meta-monitoring |
| **Logs** | Promtail DaemonSet | Stdout/stderr cua MOI pod (kube-system, argocd, monitoring, retail-store,...) |

### CHUA co (scope Phase 3.2 tro di)

- Application metrics cua UI service (HTTP rate, latency p95, 5xx rate, business metrics)
- PrometheusRule custom + Alertmanager routing Slack/Email
- Distributed tracing (Tempo/Jaeger)
- ServiceMonitor cho 5 microservice

---

## Kien truc

```
┌─────────────────────────────────────────────────────────────┐
│                  Namespace: monitoring                      │
│                                                             │
│  ┌─────────────┐   scrape    ┌──────────────────────────┐   │
│  │ Prometheus  │◄────────────┤ kube-state-metrics       │   │
│  │  (TSDB)     │◄────────────┤ node-exporter (DaemonSet)│   │
│  │  20Gi gp3   │◄────────────┤ kubelet / cAdvisor       │   │
│  │  retention  │             │ ServiceMonitors          │   │
│  │  15 ngay    │             └──────────────────────────┘   │
│  └─────┬───────┘                                            │
│        │ query                                              │
│        ▼                                                    │
│  ┌─────────────┐       query      ┌─────────────────────┐   │
│  │  Grafana    │──────────────────►│ Loki (SingleBinary) │   │
│  │  5Gi gp3    │                   │ 10Gi gp3, 7d retention   │
│  │  ClusterIP  │                   └─────────▲───────────┘   │
│  └─────┬───────┘                             │ push          │
│        │                                     │               │
│        │                          ┌──────────┴──────────┐    │
│        │                          │ Promtail (DaemonSet)│    │
│        │                          │ tail /var/log/pods/*│    │
│        │                          └─────────────────────┘    │
│        │                                                     │
│        │ kubectl port-forward 3000:80                        │
└────────┼─────────────────────────────────────────────────────┘
         ▼
      DevOps browser
```

---

## Cau truc thu muc

```
06-monitoring/
├── README.md                             # File nay
├── storageclass-gp3.yaml                 # Default StorageClass dung CSI provisioner
├── values-kube-prometheus-stack.yaml     # Override chart defaults cho t3.large nodes
├── values-loki.yaml                      # Loki SingleBinary mode config
├── values-promtail.yaml                  # Promtail DaemonSet config
└── dashboards/
    ├── apply-dashboards.ps1              # Script PowerShell dong goi JSON -> ConfigMap
    ├── node-exporter-full.json           # Grafana dashboard 1860
    ├── k8s-cluster-monitoring.json       # Grafana dashboard 315
    ├── logs-app-loki.json                # Grafana dashboard 13639
    └── k8s-views-pods.json               # Grafana dashboard 15760
```

---

## Prerequisites

| Yeu cau | Tai sao |
|---------|---------|
| EKS cluster `ecommerce-cluster` dang chay | Target deploy |
| `kubectl` tro dung context | Moi lenh apply deu can |
| **EBS CSI driver addon** (installed via Terraform o `02-cluster-eks`) | Bat buoc — K8s 1.31 da deprecate in-tree provisioner `kubernetes.io/aws-ebs`. Khong co CSI driver, PVC cua Prometheus/Loki/Grafana se Pending vinh vien |
| StorageClass `gp3` la default, provisioner `ebs.csi.aws.com` | Bien trong values files tham chieu `gp3` |
| `helm` >= 3.12 tren may local | Tool deploy |
| (optional) `metrics-server` | De `kubectl top nodes/pods` hoat dong — khong bat buoc cho stack nay vi Prometheus thu metric doc lap |

### Smoke check truoc khi deploy

```powershell
kubectl get nodes                                                   # Ready
kubectl get pods -n kube-system | Select-String "ebs-csi"           # Co controller + node daemonset
kubectl get storageclass                                            # gp3 (default), provisioner ebs.csi.aws.com
```

Neu thieu CSI driver, cai qua Terraform tai module `02-cluster-eks/irsa-ebs-csi.tf` + `cluster_addons` trong `eks.tf`.

---

## Trien khai

### Buoc 1 — StorageClass gp3 (neu chua co)

```powershell
cd infrastructure/06-monitoring
kubectl apply -f storageclass-gp3.yaml

# Bo flag default cua gp2 (neu dang la default)
kubectl patch storageclass gp2 -p '{\"metadata\": {\"annotations\":{\"storageclass.kubernetes.io/is-default-class\":\"false\"}}}'

kubectl get storageclass
# → gp3 phai co "(default)", provisioner = ebs.csi.aws.com
```

### Buoc 2 — Namespace

```powershell
kubectl create namespace monitoring
kubectl label namespace monitoring purpose=observability
```

### Buoc 3 — Helm repos

```powershell
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
```

### Buoc 4 — Sinh password Grafana

```powershell
# Windows PowerShell
$GRAFANA_PASSWORD = -join ((65..90) + (97..122) + (48..57) | Get-Random -Count 24 | ForEach-Object {[char]$_})
Write-Host "Grafana admin password: $GRAFANA_PASSWORD"
```

**Luu password vao password manager.** Khong commit vao Git.

### Buoc 5 — Cai kube-prometheus-stack

```powershell
helm install kps prometheus-community/kube-prometheus-stack `
  --namespace monitoring `
  --version 58.0.0 `
  -f values-kube-prometheus-stack.yaml `
  --set grafana.adminPassword="$GRAFANA_PASSWORD" `
  --wait --timeout 10m
```

Verify:
```powershell
kubectl -n monitoring get pods    # ~7 pod Running
kubectl -n monitoring get pvc     # 3 PVC Bound, storageClass gp3
```

### Buoc 6 — Cai Loki + Promtail

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

Verify:
```powershell
# Loki ready
kubectl -n monitoring run curl-test --rm -it --image=curlimages/curl --restart=Never -- curl -s http://loki.monitoring.svc.cluster.local:3100/ready
# → "ready"

# Promtail DaemonSet
kubectl -n monitoring get daemonset promtail    # DESIRED = READY = so node
```

### Buoc 7 — Import dashboards

```powershell
cd dashboards
.\apply-dashboards.ps1
```

Script dung `kubectl apply --server-side` (bypass gioi han 256KB cua annotation `last-applied-configuration` cho cac dashboard lon).

Verify:
```powershell
kubectl -n monitoring get configmap -l grafana_dashboard=1
# → 4 ConfigMap

kubectl -n monitoring logs deployment/kps-grafana -c grafana-sc-dashboard --tail=20 | Select-String "Writing"
# → 4 dong "Writing /tmp/dashboards/Kubernetes/dashboard-*.json"
```

---

## Truy cap Grafana

### Port-forward (khuyen nghi cho dev)

```powershell
kubectl -n monitoring port-forward svc/kps-grafana 3000:80
```

Browser: `http://localhost:3000`
- Username: `admin`
- Password: gia tri `$GRAFANA_PASSWORD` tu Buoc 4

### Lay lai password neu mat

```powershell
kubectl -n monitoring get secret kps-grafana -o jsonpath="{.data.admin-password}" | ForEach-Object { [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($_)) }
```

### Expose ra public (dem khi demo hoi dong)

Doi `service.type: ClusterIP` -> `LoadBalancer` trong `values-kube-prometheus-stack.yaml`, roi:
```powershell
helm upgrade kps prometheus-community/kube-prometheus-stack -n monitoring -f values-kube-prometheus-stack.yaml
kubectl -n monitoring get svc kps-grafana    # EXTERNAL-IP = ELB hostname
```

**Nho revert ve ClusterIP sau khi demo** de tiet kiem $18/thang ELB.

---

## Dashboards

4 dashboard duoc import tu Grafana.com community:

| ID | Ten | Tac dung |
|----|-----|----------|
| **1860** | Node Exporter Full | System metrics per node (CPU/RAM/Disk/Network) |
| **315** | Kubernetes Cluster Monitoring | Pod count, namespace resource usage |
| **13639** | Logs / App (Loki) | Log viewer realtime theo namespace/pod |
| **15760** | Kubernetes Views / Pods | Pod drill-down (CPU/RAM/restarts per pod) |

Dashboard duoc dong goi qua ConfigMap + Grafana sidecar pattern:
- Moi dashboard = 1 ConfigMap
- Label `grafana_dashboard=1` -> sidecar detect
- Annotation `grafana_folder=Kubernetes` -> gom vao folder

Them dashboard moi: tai JSON tu https://grafana.com/grafana/dashboards/ -> `dashboards/ten-file.json` -> chay lai `apply-dashboards.ps1`.

---

## Cac query mau

### Prometheus (Explore -> Prometheus)

```promql
# Top 5 namespace dung nhieu RAM
topk(5, sum by (namespace) (container_memory_working_set_bytes))

# CPU usage cua UI container
rate(container_cpu_usage_seconds_total{namespace="retail-store", pod=~"ui-.*"}[5m])

# Pod restart nhieu nhat 24h qua
topk(10, increase(kube_pod_container_status_restarts_total[24h]))

# Node nao sap het disk (<10%)
100 - (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"} * 100) > 90

# EKS API server request rate per verb
sum(rate(apiserver_request_total[5m])) by (verb)
```

### Loki (Explore -> Loki)

```logql
# Log cua namespace app
{namespace="retail-store"}

# Log cua 1 pod cu the
{namespace="retail-store", pod="ui-abc-xyz"}

# Tim error trong namespace monitoring
{namespace="monitoring"} |= "error"

# Dem so error/phut theo pod
sum by (pod) (count_over_time({namespace="retail-store"} |= "ERROR" [5m]))

# Log ArgoCD sync (debug GitOps)
{namespace="argocd"} |= "sync"
```

---

## Known issues

### 1. `serviceMonitor.enabled=false` cho Promtail

**Van de:** Chart `grafana/promtail` v6.16.0 render sai template `service-metrics.yaml` khi `serviceMonitor.enabled=true`, ket qua YAML malformed, install fail.

**Workaround hien tai:** Tat `serviceMonitor.enabled: false` trong `values-promtail.yaml`.

**He qua:** Prometheus khong scrape metrics cua chinh Promtail (log-shipped rate, errors). Log pipeline van hoat dong binh thuong.

**Fix cho tuong lai:** Tao ServiceMonitor tay qua manifest rieng:
```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: promtail
  namespace: monitoring
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: promtail
  endpoints:
    - port: http-metrics
```

Hoac chuyen sang chart moi hon (v6.17+) khi bug duoc fix upstream.

### 2. Import dashboard lon fail voi `apply` mac dinh

**Van de:** Dashboard `node-exporter-full` (~250KB) vuot gioi han 262144 bytes cua annotation `kubectl.kubernetes.io/last-applied-configuration`.

**Fix:** Script `apply-dashboards.ps1` da dung `kubectl apply --server-side=true --force-conflicts` — server-side apply khong luu annotation do.

### 3. EKS control plane metrics "DOWN"

**Van de:** Prometheus UI (`localhost:9090/targets`) hien `kubeControllerManager`, `kubeScheduler`, `kubeProxy`, `kubeEtcd` la DOWN.

**Ly do:** EKS managed control plane — khong expose port scrape cho external.

**Fix:** Da tat trong `values-kube-prometheus-stack.yaml`:
```yaml
kubeEtcd: { enabled: false }
kubeControllerManager: { enabled: false }
kubeScheduler: { enabled: false }
kubeProxy: { enabled: false }
```

### 4. `kubectl top` khong hoat dong (neu khong cai metrics-server)

**Ly do:** `kubectl top` dung API `metrics.k8s.io`, phai co `metrics-server` deployment trong `kube-system`. Prometheus KHAC voi `metrics-server`.

**Fix:**
```powershell
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

---

## Teardown

### Chi go monitoring (giu cluster)

```powershell
helm uninstall promtail -n monitoring
helm uninstall loki -n monitoring
helm uninstall kps -n monitoring

# Xoa PVC (helm khong tu xoa)
kubectl -n monitoring delete pvc --all

# Xoa namespace (bao gom ConfigMap dashboards)
kubectl delete namespace monitoring

# (Optional) Xoa CRDs cua Prometheus Operator — chi lam khi khong con app nao dung ServiceMonitor/PrometheusRule
kubectl get crd -o name | Select-String "monitoring.coreos.com" | ForEach-Object { kubectl delete $_ }
```

### Destroy toan cluster

Khi chay `terraform destroy` module `02-cluster-eks`, toan bo namespace `monitoring` se bi xoa cung cluster. **Khong can uninstall helm release truoc.**

Tuy nhien PVC co kem EBS volume — EKS managed cleanup se xoa khi xoa cluster. Kiem tra AWS Console > EC2 > Volumes sau teardown, neu co volume mo coi (status `available`, khong attached), xoa tay de tranh tinh phi.

---

## Lessons learned

1. **EBS CSI driver la MUST-HAVE tu K8s 1.23+** — in-tree provisioner bi deprecate, plugin CSI la default moi.
2. **Server-side apply** giai quyet gioi han 256KB cua client-side apply — nho khi xu ly file JSON lon.
3. **Version pin** (`--version X.Y.Z`) bat buoc cho moi helm install de reproducible.
4. **Password qua `--set`** thay vi commit — nguyen tac "secrets out-of-band".
5. **ConfigMap + sidecar pattern** cho dashboards — GitOps-ready, dashboard la code.
6. **One namespace per concern** — `monitoring` isolation voi app, de delete clean.
7. **Resource requests/limits explicit** cho tung component — khong de mac dinh tranh contention.
8. **Verify tung buoc** — khong install xong moi check tat ca, debug som re hon.

---

> Chi tiet trien khai tung buoc, xem muc [Phase 3 — Monitoring](../README.md#phase-3--trien-khai-monitoring) trong README chinh cua infrastructure.
