# ============================================
# StockOps 애플리케이션 메트릭 수집 (ServiceMonitor)
# kube-prometheus-stack의 Prometheus가 앱의 메트릭 엔드포인트를 스크래핑
# CRD(monitoring.coreos.com/v1)는 helm_release.kube_prometheus_stack이 생성
# ============================================

# stockops-api (Spring Boot) 메트릭
resource "kubernetes_manifest" "stockops_api_servicemonitor" {
  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "ServiceMonitor"
    metadata = {
      name      = "stockops-api"
      namespace = "monitoring"
      labels = {
        # kube-prometheus-stack은 이 라벨이 붙은 ServiceMonitor만 자동 인식
        release = "kube-prometheus-stack"
      }
    }
    spec = {
      namespaceSelector = {
        matchNames = ["stockops"]
      }
      selector = {
        matchLabels = {
          # TODO(내일확인): 실제 Service 라벨. kubectl get svc -n stockops --show-labels
          app = "stockops-api"
        }
      }
      endpoints = [
        {
          # TODO(내일확인): Service 포트 "이름"(숫자 아님). kubectl get svc stockops-api -n stockops -o yaml
          targetPort = 8080
          path     = "/actuator/prometheus"
          interval = "30s"
        }
      ]
    }
  }

  depends_on = [helm_release.kube_prometheus_stack]
}

# stockops-ai (FastAPI) 메트릭
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
      namespaceSelector = {
        matchNames = ["stockops"]
      }
      selector = {
        matchLabels = {
          # TODO(내일확인): FastAPI Service 라벨
          app = "stockops-ai"
        }
      }
      endpoints = [
        {
          # TODO(내일확인): FastAPI는 보통 /metrics (Spring의 /actuator/prometheus 아님)
          port     = "http"
          path     = "/metrics"
          interval = "30s"
        }
      ]
    }
  }

  depends_on = [helm_release.kube_prometheus_stack]
}