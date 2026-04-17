# 06-monitoring — Observability Stack

Monitoring stack for the EKS cluster: **Prometheus + Grafana + Loki + Promtail**.

Deployment method: **Helm imperative (Option A)**. Will migrate to GitOps (Option B, ArgoCD-managed) in Phase 3.2.

---

## Table of Contents

- [Purpose & Scope](#purpose--scope)
- [Architecture](#architecture)
- [Directory Structure](#directory-structure)
- [Prerequisites](#prerequisites)
- [Deployment](#deployment)
- [Access Grafana](#access-grafana)
- [Dashboards](#dashboards)
- [Sample Queries](#sample-queries)
- [Teardown (Cleanup After Each Lab)](#teardown-cleanup-after-each-lab)

---

## Purpose & Scope

### What is being monitored (after Phase 3.1)

| Layer | Component | Collected data |
|-------|-----------|----------------|
| **System** | `node-exporter` (DaemonSet) | CPU/RAM/Disk/Network for every EKS worker node |
| **Platform** | `kube-state-metrics` | Pod/Deployment/PVC state, restart count, OOMKill |
| **Platform** | `kubelet / cAdvisor` (EKS built-in) | CPU/RAM per container |
| **Platform** | EKS API server | Request rate, latency per verb |
| **Self** | Prometheus, Loki, Grafana, Alertmanager | Meta-monitoring |
| **Logs** | Promtail DaemonSet | Stdout/stderr of every pod (kube-system, argocd, monitoring, retail-store, ...) |

### Not yet covered (scope Phase 3.2+)

- Application metrics for the UI service (HTTP rate, latency p95, 5xx rate, business metrics)
- Custom `PrometheusRule` + Alertmanager routing to Slack / Email
- Distributed tracing (Tempo / Jaeger)
- ServiceMonitor for the 5 microservices

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                  Namespace: monitoring                      │
│                                                             │
│  ┌─────────────┐   scrape    ┌──────────────────────────┐   │
│  │ Prometheus  │◄────────────┤ kube-state-metrics       │   │
│  │  (TSDB)     │◄────────────┤ node-exporter (DaemonSet)│   │
│  │  20Gi gp3   │◄────────────┤ kubelet / cAdvisor       │   │
│  │  15d retent │             │ ServiceMonitors          │   │
│  └─────┬───────┘             └──────────────────────────┘   │
│        │ query                                              │
│        ▼                                                    │
│  ┌─────────────┐       query      ┌─────────────────────┐   │
│  │  Grafana    │──────────────────►│ Loki (SingleBinary) │   │
│  │  5Gi gp3    │                   │ 10Gi gp3, 7d retent │   │
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

## Directory Structure

```
06-monitoring/
├── README.md                             # This file
├── storageclass-gp3.yaml                 # Default StorageClass using the CSI provisioner
├── values-kube-prometheus-stack.yaml     # Chart values tuned for t3.large nodes
├── values-loki.yaml                      # Loki SingleBinary mode config
├── values-promtail.yaml                  # Promtail DaemonSet config
└── dashboards/
    ├── apply-dashboards.ps1              # PowerShell script packaging JSON → ConfigMap
    ├── node-exporter-full.json           # Grafana dashboard 1860
    ├── k8s-cluster-monitoring.json       # Grafana dashboard 315
    ├── logs-app-loki.json                # Grafana dashboard 13639
    └── k8s-views-pods.json               # Grafana dashboard 15760
```

---

## Prerequisites

| Requirement | Why |
|-------------|-----|
| EKS cluster `ecommerce-cluster` is running | Target for deployment |
| `kubectl` points at the right context | Every apply depends on it |
| **EBS CSI driver addon** (installed via Terraform in `02-cluster-eks`) | Required — K8s 1.31 deprecated the in-tree `kubernetes.io/aws-ebs` provisioner. Without CSI, the Prometheus / Loki / Grafana PVCs remain Pending forever |
| StorageClass `gp3` as default, provisioner `ebs.csi.aws.com` | Values files reference `gp3` |
| `helm` >= 3.12 locally | Deployment tool |
| (optional) `metrics-server` | Makes `kubectl top nodes/pods` work — not required for the stack since Prometheus collects metrics independently |

### Smoke check before deploying

```powershell
kubectl get nodes                                                   # Ready
kubectl get pods -n kube-system | Select-String "ebs-csi"           # Must have controller + node daemonset
kubectl get storageclass                                            # gp3 (default), provisioner ebs.csi.aws.com
```

If the CSI driver is missing, apply it via Terraform in `02-cluster-eks/irsa-ebs-csi.tf` + `cluster_addons` in `eks.tf`.

---

## Deployment

### Step 1 — StorageClass gp3 (if not present)

```powershell
cd infrastructure/06-monitoring
kubectl apply -f storageclass-gp3.yaml

# Remove the default flag from gp2 (if it is currently default)
kubectl patch storageclass gp2 -p '{\"metadata\": {\"annotations\":{\"storageclass.kubernetes.io/is-default-class\":\"false\"}}}'

kubectl get storageclass
# → gp3 should show "(default)", provisioner = ebs.csi.aws.com
```

### Step 2 — Namespace

```powershell
kubectl create namespace monitoring
kubectl label namespace monitoring purpose=observability
```

### Step 3 — Helm repos

```powershell
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
```

### Step 4 — Generate a Grafana password

```powershell
# Windows PowerShell
$GRAFANA_PASSWORD = -join ((65..90) + (97..122) + (48..57) | Get-Random -Count 24 | ForEach-Object {[char]$_})
Write-Host "Grafana admin password: $GRAFANA_PASSWORD"
```

**Store this password in a password manager.** Never commit it to Git.

### Step 5 — Install kube-prometheus-stack

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
kubectl -n monitoring get pods    # ~7 pods Running
kubectl -n monitoring get pvc     # 3 PVCs Bound, storageClass gp3
```

### Step 6 — Install Loki + Promtail

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
kubectl -n monitoring get daemonset promtail    # DESIRED = READY = number of nodes
```

### Step 7 — Import dashboards

```powershell
cd dashboards
.\apply-dashboards.ps1
```

The script uses `kubectl apply --server-side` to bypass the 256KB annotation limit of client-side apply (the 1860 dashboard is close to that limit).

Verify:
```powershell
kubectl -n monitoring get configmap -l grafana_dashboard=1
# → 4 ConfigMaps

kubectl -n monitoring logs deployment/kps-grafana -c grafana-sc-dashboard --tail=20 | Select-String "Writing"
# → 4 lines "Writing /tmp/dashboards/Kubernetes/dashboard-*.json"
```

---

## Access Grafana

### Port-forward (recommended for dev)

```powershell
kubectl -n monitoring port-forward svc/kps-grafana 3000:80
```

Browser: `http://localhost:3000`
- Username: `admin`
- Password: the `$GRAFANA_PASSWORD` value from Step 4

### Recover the password if lost

```powershell
kubectl -n monitoring get secret kps-grafana -o jsonpath="{.data.admin-password}" | ForEach-Object { [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($_)) }
```

### Expose publicly (only during a demo)

Change `service.type: ClusterIP` → `LoadBalancer` in `values-kube-prometheus-stack.yaml`, then:
```powershell
helm upgrade kps prometheus-community/kube-prometheus-stack -n monitoring -f values-kube-prometheus-stack.yaml
kubectl -n monitoring get svc kps-grafana    # EXTERNAL-IP = ELB hostname
```

**Remember to revert to `ClusterIP` after the demo** to avoid the $18/month ELB charge.

---

## Dashboards

4 dashboards are imported from the Grafana.com community:

| ID | Name | Purpose |
|----|------|---------|
| **1860** | Node Exporter Full | System metrics per node (CPU/RAM/Disk/Network) |
| **315** | Kubernetes Cluster Monitoring | Pod count, namespace resource usage |
| **13639** | Logs / App (Loki) | Real-time log viewer by namespace/pod |
| **15760** | Kubernetes Views / Pods | Pod drill-down (CPU/RAM/restarts per pod) |

Dashboards are packaged via the **ConfigMap + Grafana sidecar** pattern:
- Each dashboard = one ConfigMap
- Label `grafana_dashboard=1` → detected by the sidecar
- Annotation `grafana_folder=Kubernetes` → grouped into one folder

To add a new dashboard: download JSON from https://grafana.com/grafana/dashboards/ → `dashboards/<name>.json` → re-run `apply-dashboards.ps1`.

---

## Sample Queries

### Prometheus (Explore → Prometheus)

```promql
# Top 5 namespaces by RAM usage
topk(5, sum by (namespace) (container_memory_working_set_bytes))

# CPU usage of the UI container
rate(container_cpu_usage_seconds_total{namespace="retail-store", pod=~"ui-.*"}[5m])

# Pods with the most restarts over the last 24h
topk(10, increase(kube_pod_container_status_restarts_total[24h]))

# Nodes running low on disk (<10%)
100 - (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"} * 100) > 90

# EKS API server request rate per verb
sum(rate(apiserver_request_total[5m])) by (verb)
```

### Loki (Explore → Loki)

```logql
# Logs from the app namespace
{namespace="retail-store"}

# Logs from a specific pod
{namespace="retail-store", pod="ui-abc-xyz"}

# Errors inside the monitoring namespace
{namespace="monitoring"} |= "error"

# Error count per minute per pod
sum by (pod) (count_over_time({namespace="retail-store"} |= "ERROR" [5m]))

# ArgoCD sync logs (GitOps debugging)
{namespace="argocd"} |= "sync"
```

---

## Teardown (Cleanup After Each Lab)

Running the monitoring stack continuously costs ~$4/month (EBS volumes) plus compute overhead on the cluster. If you are pausing the lab, uninstall the stack to release EBS volumes.

### Uninstall monitoring only (keep the cluster)

```powershell
helm uninstall promtail -n monitoring
helm uninstall loki -n monitoring
helm uninstall kps -n monitoring

# Delete PVCs (helm does not remove them)
kubectl -n monitoring delete pvc --all

# Delete the namespace (includes dashboard ConfigMaps)
kubectl delete namespace monitoring

# (Optional) Delete Prometheus Operator CRDs — only if no app still depends on ServiceMonitor / PrometheusRule
kubectl get crd -o name | Select-String "monitoring.coreos.com" | ForEach-Object { kubectl delete $_ }
```

### Destroy the whole cluster

When you run `terraform destroy` on `02-cluster-eks`, the entire `monitoring` namespace is deleted together with the cluster. **You do not need to uninstall the helm releases first.**

However, PVCs are backed by EBS volumes — EKS-managed cleanup should remove them along with the cluster. After teardown, check **AWS Console > EC2 > Volumes** and delete any orphaned volumes (status `available`, not attached) to avoid storage charges.

---

> Step-by-step deployment details are covered in [Phase 3 — Monitoring Deployment](../README.md#phase-3--monitoring-deployment) in the main infrastructure README.
