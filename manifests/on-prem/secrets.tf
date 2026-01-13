resource "kubernetes_secret" "cloudflare_token" {
  metadata {
    name      = "cloudflare-token"
    namespace = "kube-system"
  }
  data = {
    token = var.cloudflare_token # 직접 적지 않고 변수를 호출!
  }
}