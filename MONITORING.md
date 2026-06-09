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
| Grafana | 대시보드 시각화 | NLB LoadBalancer로 외부 노출 |
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

### 설계 의도

범용 인프라 메트릭은 커뮤니티에서 이미 검증된 공식 템플릿을 활용하고,
StockOps 서비스에 특화된 메트릭(서비스별 Pod 상태, 네트워크 등)은 직접 제작하는 방식을 채택했습니다.

> "검증된 도구는 활용하고, 서비스 특화 부분은 직접 구현한다"

| 구분 | 방식 | 이유 |
|------|------|------|
| 공식 템플릿 | Grafana Community ID | 노드/클러스터 범용 메트릭은 이미 최적화된 템플릿 활용 |
| 커스텀 대시보드 | Terraform jsonencode | stockops 네임스페이스 특화, GitOps로 버전 관리 |

### 공식 템플릿 활용

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

| 서브넷 | 태그 키 | 태그 값 |
|-------|--------|--------|
| 퍼블릭 | `kubernetes.io/role/elb` | `1` |
| 퍼블릭 | `kubernetes.io/cluster/seoul-cluster` | `shared` |
| 프라이빗 앱 | `kubernetes.io/role/internal-elb` | `1` |
| 프라이빗 앱 | `kubernetes.io/cluster/seoul-cluster` | `shared` |

---

## 🗄️ Terraform Remote Backend (S3)

### 설계 목적

팀 프로젝트 특성상 학원 PC, 개인 노트북 등 여러 환경에서 작업이 필요했습니다.
로컬 tfstate는 환경이 바뀔 때마다 상태를 잃거나 충돌이 발생하는 문제가 있었고,
이를 해결하기 위해 S3 Remote Backend를 도입했습니다.

| 목적 | 설명 |
|------|------|
| 팀 협업 | tfstate 중앙 관리로 상태 충돌 방지 |
| 보안 | 민감 정보 GitHub 노출 차단 |
| 가용성 | 어느 PC에서든 동일한 상태로 작업 가능 |
| 복구 | S3 버저닝으로 tfstate 변경 이력 관리 |

```hcl
terraform {
  backend "s3" {
    bucket  = "siseon-terraform-state"
    key     = "monitoring/terraform.tfstate"
    region  = "ap-northeast-2"
    profile = "siseon"
  }
}
```

---

## 🧪 부하 테스트 (k6)

Grafana 대시보드의 실시간 메트릭 변화를 검증하기 위해 k6 부하 테스트를 수행했습니다.

### 테스트 구성

```javascript
import http from 'k6/http';
import { sleep } from 'k6';

export const options = {
  vus: 10,        // 가상 유저 10명
  duration: '30s' // 30초 동안
};

export default function () {
  http.get('http://<ALB_DNS>/api/actuator/health');
  sleep(1);
}
```

### 테스트 결과

- **⚡ Pod CPU 사용률**: 부하 발생 시 급격한 상승 확인
- **💡 Pod 메모리 사용량**: 트래픽 증가에 따른 메모리 변화 확인
- **📥📤 네트워크 트래픽**: 요청/응답 트래픽 실시간 시각화 확인

> Grafana 대시보드에서 부하 테스트 중 메트릭이 실시간으로 반영되는 것을 확인하여
> 모니터링 파이프라인의 정상 동작을 검증했습니다.

## 📧 Grafana Alertmanager 이메일 알람

### 설계 목적
인프라 임계값 초과 시 관리자(bljh5220@gmail.com)에게 즉시 이메일 알람을 발송합니다.
관리자가 알람 수신 후 즉시 대응하는 시나리오를 구성합니다.

### 구성

| 항목 | 값 |
|------|-----|
| SMTP 서버 | smtp.gmail.com:587 |
| 발신 계정 | bljh5220@gmail.com |
| 수신 계정 | bljh5220@gmail.com |
| 인증 방식 | Gmail 앱 비밀번호 |
| TLS | 필수 |

### 알람 라우팅

| 심각도 | 조건 | 수신자 |
|--------|------|--------|
| critical | 즉시 발송 | 관리자 |
| warning | 즉시 발송 | 관리자 |
| resolved | 복구 시 발송 | 관리자 |

### 반복 알람 설정

| 항목 | 값 | 의미 |
|------|-----|------|
| group_wait | 30s | 첫 알람 대기 시간 |
| group_interval | 5m | 동일 그룹 재알람 간격 |
| repeat_interval | 12h | 미해결 알람 반복 간격 |