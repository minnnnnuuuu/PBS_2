# -----------------------------------------------------------
# [최종 수정] EKS 하이브리드 관제 (To 온프레미스 본부)
# -----------------------------------------------------------

# 1. 지표 배달부 (Prometheus Agent)
resource "helm_release" "prometheus_agent" {
  name             = "prometheus-agent-v3" # [변경] 이름 충돌 방지
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "prometheus"
  namespace        = "monitoring"
  create_namespace = true
  
  # [핵심] 테라폼이 무한 대기하지 않게 설정 (에러 방지)
  wait = false

  # [설정] 하드디스크 끄기 + 본사 전송
  values = [<<EOF
server:
  persistentVolume:
    enabled: false
  remoteWrite:
    - url: "https://prometheus.cloudreaminu.cloud/api/v1/write"
  global:
    external_labels:
      cluster: "pbs-eks-dev"

# 불필요한 기능 끄기
alertmanager:
  enabled: false
pushgateway:
  enabled: false
nodeExporter:
  enabled: true
kubeStateMetrics:
  enabled: true
EOF
  ]

  depends_on = [module.eks]
}

# 2. 로그 배달부 (Promtail)
resource "helm_release" "promtail" {
  name             = "promtail"
  repository       = "https://grafana.github.io/helm-charts"
  chart            = "promtail"
  namespace        = "monitoring"
  create_namespace = true 
  
  # 여기도 대기하지 않고 즉시 완료 처리
  wait = false

  values = [<<EOF
config:
  clients:
    - url: "https://loki.cloudreaminu.cloud/loki/api/v1/push"
      external_labels:
        cluster: "pbs-eks-dev"
EOF
  ]

  depends_on = [module.eks]
}