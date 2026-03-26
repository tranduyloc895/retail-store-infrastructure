resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "5.51.4" 
  
  namespace        = "argocd"
  create_namespace = true     

  depends_on = [module.eks]
}