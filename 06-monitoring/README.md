# 06-monitoring — Observability Stack

Deployment method: **Helm imperative (Option A)**. Sẽ migrate sang GitOps (Option B) ở Phase 3.2.

## Stack
- `kube-prometheus-stack` — Prometheus + Alertmanager + Grafana + node-exporter + kube-state-metrics
- `loki` — log aggregation (single-binary mode)
- `promtail` — log shipper (DaemonSet)

## Files
```
06-monitoring/
├── values-kube-prometheus-stack.yaml   # Prometheus + Grafana config
├── values-loki.yaml                    # Loki single-binary config
├── values-promtail.yaml                # Promtail config (gửi log tới Loki)
├── dashboards/                         # Grafana dashboards JSON (auto-load qua sidecar)
└── README.md
```

## Prerequisites
- EKS cluster đã chạy (module `02-cluster-eks`)
- `kubectl` trỏ đúng context
- EBS CSI driver addon enabled
- Helm >= 3.12

## Quick start
Xem hướng dẫn chi tiết trong README gốc `infrastructure/README.md`, mục "Phase 3 — Monitoring".
