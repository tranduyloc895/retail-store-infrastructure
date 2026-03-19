resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "5.51.4" 
  
  namespace        = "argocd"
  create_namespace = true     

  depends_on = [module.eks]

  # Tùy chỉnh (Trade-off): Bỏ qua bước kiểm tra SSL nếu dùng repo nội bộ (ở đồ án này ta dùng public nên không cần)
  # set {
  #   name  = "server.insecure"
  #   value = "true"
  # }
}