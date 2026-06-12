# ============================================
# StockOps 애플리케이션 메트릭 수집 (ServiceMonitor)
# kube-prometheus-stack의 Prometheus가 앱의 메트릭 엔드포인트를 스크래핑
# CRD(monitoring.coreos.com/v1)는 helm_release.kube_prometheus_stack이 생성
# - 클린 배포 시 2단계 apply 필요 (TROUBLESHOOTING #12)
# ============================================

# stockops-api (Spring Boot) — /actuator/prometheus
resource "kubernetes_manifest" "stockops_api_servicemonitor" {
  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "ServiceMonitor"
    metadata = {
      name      = "stockops-api"
      namespace = "monitoring"
      labels = {
        release = "kube-prometheus-stack"
      }
    }
    spec = {
      selector = {
        matchLabels = {
          app = "stockops-api"
        }
      }
      namespaceSelector = {
        matchNames = ["stockops"]
      }
      endpoints = [
        {
          port     = "http"
          path     = "/actuator/prometheus"
          interval = "30s"
        }
      ]
    }
  }
  depends_on = [helm_release.kube_prometheus_stack]
}

# stockops-ai (FastAPI) — /metrics (prometheus-fastapi-instrumentator)
resource "kubernetes_manifest" "stockops_ai_servicemonitor" {
  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "ServiceMonitor"
    metadata = {
      name      = "stockops-ai"
      namespace = "monitoring"
      labels = {
        release = "kube-prometheus-stack"
      }
    }
    spec = {
      selector = {
        matchLabels = {
          app = "stockops-ai"
        }
      }
      namespaceSelector = {
        matchNames = ["stockops"]
      }
      endpoints = [
        {
          port     = "http"
          path     = "/metrics"
          interval = "30s"
        }
      ]
    }
  }
  depends_on = [helm_release.kube_prometheus_stack]
}