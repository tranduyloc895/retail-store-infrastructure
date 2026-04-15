# =============================================================================
# apply-dashboards.ps1 (PowerShell)
# -----------------------------------------------------------------------------
# Dong goi tung file JSON thanh ConfigMap co label grafana_dashboard=1.
# Grafana sidecar se tu detect va load vao UI trong ~30s.
#
# Dung server-side apply de tranh gioi han 256KB cua annotation
# kubectl.kubernetes.io/last-applied-configuration (cac dashboard lon
# nhu node-exporter-full vuot nguong nay).
# =============================================================================

$Namespace = "monitoring"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

Get-ChildItem -Path $ScriptDir -Filter "*.json" | ForEach-Object {
    $JsonFile = $_.FullName
    $FileName = $_.BaseName
    $ConfigMapName = "dashboard-$FileName"

    Write-Host ">>> Applying dashboard: $FileName" -ForegroundColor Cyan

    # Tao ConfigMap YAML, apply bang server-side (bypass gioi han annotation 256KB)
    kubectl create configmap $ConfigMapName `
        --namespace=$Namespace `
        --from-file="$FileName.json=$JsonFile" `
        --dry-run=client -o yaml | `
    kubectl apply --server-side=true --force-conflicts -f -

    # Gan label de sidecar nhan dien
    kubectl label configmap $ConfigMapName `
        --namespace=$Namespace `
        grafana_dashboard=1 --overwrite

    # Gom vao folder "Kubernetes" trong Grafana
    kubectl annotate configmap $ConfigMapName `
        --namespace=$Namespace `
        grafana_folder="Kubernetes" --overwrite
}

Write-Host ""
Write-Host "All dashboards applied. Wait ~30s for Grafana sidecar to detect." -ForegroundColor Green
Write-Host "Check: Grafana UI -> Dashboards -> folder 'Kubernetes'." -ForegroundColor Green
