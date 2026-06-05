# 🔍 StockOps 인프라 모니터링 설계 문서

> kube-prometheus-stack 기반 EKS 인프라 모니터링 구성 및 Grafana 커스텀 대시보드 설계 문서

---

## 🏗️ 전체 아키텍처

```
Amazon EKS (seoul-cluster)
│
├── stockops 네임스페이스
│   ├── stockops-api        (Spring Boot)
│   ├── stockops-ai         (FastAPI)
│   ├── stockops-client-web (React)
│   ├── stockops-admin-web  (React)
│   └── stockops-redis      (Redis)
│
└── monitoring 네임스페이스
    ├── Prometheus           ← 메트릭 수집
    ├── Node Exporter        ← 노드 시스템 메트릭
    ├── kube-state-metrics   ← 클러스터 상태 메트릭
    └── Grafana              ← 시각화 대시보드
                                    ↓
                            AWS NLB (internet-facing)
                                    ↓
                            외부 접속 (브라우저)
```

---

## 📦 kube-prometheus-stack 구성

Helm chart 단일 설치로 모니터링 스택 전체를 한 번에 배포합니다.

| 컴포넌트 | 역할 | 비고 |
|---------|------|------|
| Prometheus | 메트릭 수집 및 저장 | 보존 기간 7일 |
| Node Exporter | 노드 CPU/메모리/디스크/네트워크 수집 | DaemonSet으로 모든 노드에 배포 |
| kube-state-metrics | Pod/Deployment/Node 상태 메트릭 | K8s API 기반 |
| Grafana | 대시보드 시각화 | LoadBalancer로 외부 노출 |
| AlertManager | 비활성화 | Grafana Alerting으로 대체 예정 |

### 리소스 설정

```yaml
prometheus:
  requests:
    memory: 256Mi
    cpu: 100m
  limits:
    memory: 512Mi
    cpu: 500m
```

t3.medium(2vCPU, 4GB) 환경에 맞게 보수적으로 설정

---

## 📊 Grafana 데이터소스

| 데이터소스 | UID | 용도 |
|-----------|-----|------|
| Prometheus | `prometheus` | 인프라 메트릭 (기본) |
| CloudWatch | `cloudwatch` | 애플리케이션 로그 (추후 연동) |

### 데이터소스 중복 방지 설정

kube-prometheus-stack은 기본적으로 Prometheus 데이터소스를 자동 등록합니다.
커스텀 데이터소스 설정 시 중복으로 인한 오류를 방지하기 위해 sidecar 설정을 추가합니다.

```hcl
sidecar = {
  datasources = {
    defaultDatasourceEnabled = false
  }
}
```

---

## 🎨 대시보드 구성 전략

### 공식 템플릿 활용

커뮤니티에서 검증된 공식 대시보드를 기반으로 활용합니다.
Grafana.com의 gnetId를 통해 자동으로 가져옵니다.

| 대시보드 | gnetId | 용도 |
|---------|--------|------|
| Node Exporter Full | 1860 | 노드 상세 메트릭 |
| Kubernetes Cluster | 7249 | 클러스터 전체 현황 |
| Kubernetes Pods | 6417 | Pod 상세 메트릭 |

### 커스텀 대시보드 (🏭 StockOps 인프라 현황)

StockOps 서비스에 특화된 대시보드를 직접 제작합니다.
Terraform `yamlencode` + `jsonencode` 를 활용해 코드로 대시보드를 정의하고
Grafana provisioning을 통해 배포 시 자동으로 생성됩니다.

---

## 📈 커스텀 대시보드 패널 구성

### Row 1: 클러스터 요약 (Stat/Gauge)

| 패널 | 타입 | PromQL |
|------|------|--------|
| 🖥️ 클러스터 CPU 사용률 | gauge | `100 - (avg(irate(node_cpu_seconds_total{mode='idle'}[5m])) * 100)` |
| 💾 클러스터 메모리 사용률 | gauge | `100 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes * 100)` |
| ✅ Running Pods | stat | `count(kube_pod_status_phase{phase='Running'})` |
| 🚨 Failed Pods | stat | `count(kube_pod_status_phase{phase='Failed', namespace='stockops'}) or vector(0)` |
| 🖧 Node 수 | stat | `count(kube_node_info)` |
| ⏳ Pending Pods | stat | `count(kube_pod_status_phase{phase='Pending'}) or vector(0)` |

### Row 2: 서비스 상태 (Table)

| 패널 | 타입 | PromQL |
|------|------|--------|
| 📋 StockOps 서비스별 Pod 상태 | table | `kube_pod_status_phase{namespace='stockops'}` |

### Row 3: 리소스 사용량 (Timeseries)

| 패널 | 타입 | PromQL |
|------|------|--------|
| ⚡ Pod CPU 사용률 | timeseries | `sum(rate(container_cpu_usage_seconds_total{namespace='stockops',container!=''}[5m])) by (pod) * 100` |
| 💡 Pod 메모리 사용량 | timeseries | `sum(container_memory_working_set_bytes{namespace='stockops',container!=''}) by (pod)` |

### Row 4: 네트워크 (Timeseries)

| 패널 | 타입 | PromQL |
|------|------|--------|
| 📥 네트워크 수신 트래픽 | timeseries | `sum(rate(container_network_receive_bytes_total{namespace='stockops'}[5m])) by (pod)` |
| 📤 네트워크 송신 트래픽 | timeseries | `sum(rate(container_network_transmit_bytes_total{namespace='stockops'}[5m])) by (pod)` |

### Row 5: 상태 테이블

| 패널 | 타입 | PromQL |
|------|------|--------|
| 🔄 Pod 재시작 횟수 | table | `sum(kube_pod_container_status_restarts_total{namespace='stockops'}) by (pod)` |
| 🟢 Node 상태 | table | `kube_node_status_condition{condition='Ready',status='true'}` |

---

## ⚙️ Terraform Provisioning 방식

대시보드를 코드로 관리하는 핵심 구조입니다.

```hcl
# 1. 대시보드 프로바이더 폴더 지정
dashboardProviders = {
  "dashboardproviders.yaml" = {
    providers = [{
      name   = "infra-custom"
      folder = "📊 인프라 모니터링"
      type   = "file"
      options = { path = "/var/lib/grafana/dashboards/infra-custom" }
    }]
  }
}

# 2. 대시보드 JSON 정의 (jsonencode 사용)
dashboards = {
  infra-custom = {
    stockops-infra = {
      json = jsonencode({ ... })
    }
  }
}
```

이 방식의 장점:
- **GitOps**: 대시보드 변경 사항이 Git으로 추적됨
- **재현 가능**: `terraform apply` 한 번으로 동일한 대시보드 자동 생성
- **버전 관리**: 대시보드 히스토리 관리 가능

---

## 🌐 NLB LoadBalancer 구성

Grafana 외부 노출을 위해 AWS NLB를 사용합니다.

```hcl
service = {
  type = "LoadBalancer"
  annotations = {
    "service.beta.kubernetes.io/aws-load-balancer-scheme" = "internet-facing"
  }
}
```

### NLB 동작 흐름

```
외부 브라우저
    ↓ (HTTP:80)
AWS NLB (internet-facing)
    ↓ (TCP:30xxx NodePort)
EKS Worker Node
    ↓ (TCP:3000)
Grafana Pod
```

### 서브넷 태그 필수 조건

AWS Load Balancer Controller가 NLB를 생성하려면 서브넷에 아래 태그가 필요합니다.

| 서브넷 | 태그 키 | 태그 값 |
|-------|--------|--------|
| 퍼블릭 | `kubernetes.io/role/elb` | `1` |
| 퍼블릭 | `kubernetes.io/cluster/seoul-cluster` | `shared` |
| 프라이빗 앱 | `kubernetes.io/role/internal-elb` | `1` |
| 프라이빗 앱 | `kubernetes.io/cluster/seoul-cluster` | `shared` |