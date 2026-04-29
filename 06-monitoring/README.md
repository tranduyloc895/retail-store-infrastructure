# 06-monitoring — ARCHIVED (Migrated to GitOps)

> **⚠️ This directory has been archived as of Phase 3.2.**
>
> The monitoring stack has been migrated to GitOps-managed deployment via ArgoCD.
> The authoritative configuration now lives in **`retail-store-gitops/platform/monitoring/`**.
>
> Do **not** use the scripts in this directory to deploy to a running cluster — they will conflict with ArgoCD.

---

## Why this directory still exists

These files are kept as a historical record of the Phase 3.1 Helm-imperative deployment. They are useful for:
- Understanding what changed between Phase 3.1 and 3.2
- Comparing Helm `values-*.yaml` against the GitOps versions if a diff is ever needed
- Reference when onboarding someone who asks "how was monitoring installed before?"

---

## What was here (Phase 3.1 — Helm imperative)

| File | Purpose (historical) |
|------|---------------------|
| `storageclass-gp3.yaml` | Default StorageClass — now managed by the `platform-storageclass` ArgoCD Application |
| `values-kube-prometheus-stack.yaml` | kube-prometheus-stack Helm values — now at `platform/monitoring/values-kube-prometheus-stack.yaml` |
| `values-loki.yaml` | Loki Helm values — now at `platform/monitoring/values-loki.yaml` |
| `values-promtail.yaml` | Promtail DaemonSet values — now at `platform/monitoring/values-promtail.yaml` |
| `dashboards/apply-dashboards.ps1` | PowerShell script to create dashboard ConfigMaps — replaced by Kustomize `configMapGenerator` |
| `dashboards/*.json` | Grafana dashboard JSON files — now at `platform/monitoring/dashboards/` in the gitops repo |

---

## Where to go now (Phase 3.2+ — GitOps)

| What you need | Where to find it |
|---------------|-----------------|
| Helm values for the 3 charts | `retail-store-gitops/platform/monitoring/values-*.yaml` |
| Dashboard JSON + Kustomize | `retail-store-gitops/platform/monitoring/dashboards/` |
| ArgoCD Application definitions | `retail-store-gitops/argocd/platform-*.yml` (6 files) |
| Namespace + StorageClass manifests | `retail-store-gitops/platform/monitoring/namespace.yml` + `storageclass-gp3.yaml` |
| Bootstrap script (fresh cluster) | `retail-store-gitops/scripts/bootstrap.sh` |
| Full documentation | [`retail-store-gitops/platform/monitoring/README.md`](https://github.com/tranduyloc895/retail-store-gitops/blob/main/platform/monitoring/README.md) |

---

> *Archived in Phase 3.2. This directory is retained for historical reference only.*
