# 🔍 StockOps 모니터링 설계 문서

> kube-prometheus-stack 기반 EKS 모니터링 구성 및 Grafana 대시보드(인프라 / 애플리케이션) 설계 문서

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

Grafana는 4개 데이터소스(Prometheus / CloudWatch / Athena / 추후 X-Ray)를 한곳에 모아 인프라·애플리케이션 관측을 단일 창구로 제공한다.

---

## 📦 kube-prometheus-stack 구성

Helm chart 단일 설치로 모니터링 스택 전체를 한 번에 배포합니다.

| 컴포넌트 | 역할 | 비고 |
|---------|------|------|
| Prometheus | 메트릭 수집 및 저장 | 보존 기간 7일 |
| Node Exporter | 노드 CPU/메모리/디스크/네트워크 수집 | DaemonSet으로 모든 노드에 배포 |
| kube-state-metrics | Pod/Deployment/Node 상태 메트릭 | K8s API 기반 |
| Grafana | 대시보드 시각화 | NLB LoadBalancer로 외부 노출 |
| AlertManager | Gmail SMTP 이메일 알람 | PodFailed, NodeCPU/Memory, PodRestart |

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

| 데이터소스 | UID | 용도 | 비고 |
|-----------|-----|------|------|
| Prometheus | `prometheus` | 인프라/앱 메트릭 (기본) | 클러스터 내부 수집 |
| CloudWatch | `cloudwatch` | 애플리케이션 로그 | api/ai 로그그룹 조회 |
| Athena | `athena` | IoT 센서 데이터 | `grafana-athena-datasource` 플러그인 |

- Athena 데이터소스는 `siseon-observability`가 생성한 워크그룹(`siseon-sensor-workgroup`)·DB(`stockops_sensor`)를 참조한다. 따라서 observability 레포가 먼저 배포되어야 한다.
- CloudWatch 데이터소스는 리소스명에 묶이지 않고 region/authType만 필요하므로 로그그룹 생성 순서와 무관하다.

### 데이터소스/대시보드 sidecar 비활성화

kube-prometheus-stack의 sidecar가 데이터소스·대시보드를 중복 인식해 충돌(UID 중복)을 일으켜, 직접 provisioning만 사용하도록 sidecar를 끈다.

```hcl
sidecar = {
  datasources = { defaultDatasourceEnabled = false }
  dashboards  = { enabled = false }
}
```

---

## 📁 대시보드 폴더 구조

발표/운영 관점에 맞춰 대시보드를 **인프라 / 애플리케이션** 2개 폴더로 분리한다.

```
📊 인프라 모니터링
  ├ Node Exporter Full (1860)      ← 공식 템플릿
  ├ Kubernetes Cluster (7249)      ← 공식 템플릿
  ├ Kubernetes Pods (6417)         ← 공식 템플릿
  └ 🏭 StockOps 인프라 현황         ← 커스텀

🚀 애플리케이션 모니터링
  ├ 🌡️ StockOps IoT 센서 현황       ← Athena
  └ 📜 StockOps 애플리케이션 로그    ← CloudWatch Logs
```

> IoT 센서/앱 로그는 서버 인프라가 아니라 **비즈니스·애플리케이션 데이터**이므로 인프라 폴더와 분리했다. 같은 `folder` 값을 가진 provider는 하나의 폴더로 합쳐진다.

---

## 🎨 대시보드 구성 전략

범용 인프라 메트릭은 검증된 공식 템플릿을 활용하고, StockOps 특화 부분은 직접 제작한다.

| 구분 | 방식 | 이유 |
|------|------|------|
| 공식 템플릿 | Grafana Community ID (1860/7249/6417) | 노드/클러스터 범용 메트릭은 최적화된 템플릿 활용 |
| 커스텀 대시보드 | Terraform jsonencode | stockops 특화, GitOps로 버전 관리 |

---

## 📈 커스텀 대시보드 패널 구성

### 🏭 StockOps 인프라 현황 (Prometheus)

| Row | 패널 | 타입 |
|-----|------|------|
| 1 | 노드별 CPU / 메모리 사용률 | gauge |
| 2 | Running / Failed / Pending Pods, Node 수 | stat |
| 3 | StockOps Pod CPU / 메모리 사용량 | timeseries |
| 4 | 네트워크 수신/송신 트래픽 | timeseries |
| 5 | Pod 재시작 횟수 / Node 상태 | table |
| 6 | StockOps 서비스별 Pod 상태 | table |

- **노드별 게이지**: CPU/메모리를 노드(instance)별 게이지로 표시. 클러스터 평균 1개로 합치면 특정 노드 과부하를 놓칠 수 있어, 오토스케일링으로 노드가 늘어도 노드별로 보이게 했다. `label_replace`로 instance에서 포트(`:9100`)를 떼어 IP만 표기.
- **Pod 메모리 로그 스케일**: redis(수백 MiB)와 소형 파드(수 MiB) 간 값 차이가 커서 **로그 스케일(`scaleDistribution: log, base 2`)** 을 적용, 모든 파드를 한 화면에서 비교 가능하게 했다.
- **범례 우측 테이블**: 파드 수가 오토스케일링으로 늘면 하단 범례가 그래프를 잠식하므로, Pod/네트워크 패널의 범례를 우측 테이블(`placement: right`)로 옮기고 현재값·최대값(`lastNotNull`, `max`)을 함께 표시.

### 🌡️ StockOps IoT 센서 현황 (Athena)

| 패널 | 타입 | 센서 |
|------|------|------|
| 온도 / 습도 / 기압 | timeseries | temperature / humidity / pressure |
| PM2.5 / PM10 | timeseries | pm25 / pm10 |
| 도어 상태 / 재실 감지 | stat | door_open / presence_detected |

- `창고(site_id)` 템플릿 변수로 창고별 필터링. `includeAll = false`로 항상 실제 창고가 선택되게 함.
- 센서별 고정 색상 지정(온도=red, 습도=blue, 기압=purple, PM2.5=orange, PM10=yellow)으로 구분성 강화.
- 모든 Athena target에 `connectionArgs`(region/catalog/database) 필수.

### 📜 StockOps 애플리케이션 로그 (CloudWatch Logs)

| 패널 | 타입 | 내용 |
|------|------|------|
| API 로그 (stockops-api) | logs | api 로그그룹 실시간 조회 |
| AI 로그 (stockops-ai) | logs | ai 로그그룹 실시간 조회 |
| API 경고/에러 | logs | WARN/ERROR 필터 |

> 로그는 원문 조회·검색용이며, 에러율·응답시간 같은 집계 지표는 로그 파싱이 아니라 메트릭(Prometheus, `/actuator/prometheus`)으로 처리하는 것을 원칙으로 한다.

---

## 🔐 Grafana IRSA (Athena / CloudWatch Logs 접근)

Grafana가 Athena·CloudWatch Logs 등 AWS 서비스를 호출하려면 IAM 권한이 필요하다. EKS Node Role 방식은 Pod가 IMDS 자격증명을 가져오지 못해 실패하므로, **IRSA**로 Grafana ServiceAccount에 Role을 직접 연결한다.

```hcl
serviceAccount = {
  create = true
  name   = "grafana-athena-sa"
  annotations = {
    "eks.amazonaws.com/role-arn" = aws_iam_role.grafana_athena_role.arn
  }
}
```

연결된 정책:

| 정책 | 용도 |
|------|------|
| AmazonAthenaFullAccess | IoT 센서 Athena 쿼리 |
| AWSGlueConsoleFullAccess | Glue 카탈로그 조회 |
| AmazonS3FullAccess | Athena 쿼리 결과 쓰기 / 센서 원본 읽기 |
| CloudWatchLogsReadOnlyAccess | 앱 로그 조회 |

> IRSA Role(`seoul-grafana-athena-role`)의 신뢰관계는 OIDC issuer + `system:serviceaccount:monitoring:grafana-athena-sa`로 한정. (트러블슈팅은 observability 레포 참고)

---

## ⚙️ Terraform Provisioning 방식

대시보드를 코드로 관리하는 핵심 구조입니다.

```hcl
dashboardProviders = {
  "dashboardproviders.yaml" = {
    providers = [
      { name = "infra-custom",  folder = "📊 인프라 모니터링",      ... },
      { name = "iot-custom",    folder = "🚀 애플리케이션 모니터링", ... },
      { name = "applog-custom", folder = "🚀 애플리케이션 모니터링", ... }
    ]
  }
}

dashboards = {
  infra-custom  = { stockops-infra  = { json = jsonencode({ ... }) } }
  iot-custom    = { stockops-iot    = { json = jsonencode({ ... }) } }
  applog-custom = { stockops-applog = { json = jsonencode({ ... }) } }
}
```

장점: GitOps(변경 추적), 재현 가능(`terraform apply` 한 번), 버전 관리.

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
외부 브라우저 → AWS NLB(internet-facing) → NodePort → Grafana Pod(3000)
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

팀 프로젝트 특성상 여러 환경(학원 PC/노트북)에서 작업하므로 S3 Remote Backend로 tfstate를 중앙 관리한다.

| 목적 | 설명 |
|------|------|
| 팀 협업 | tfstate 중앙 관리로 상태 충돌 방지 |
| 보안 | 민감 정보 GitHub 노출 차단 |
| 가용성 | 어느 PC에서든 동일 상태로 작업 |
| 복구 | S3 버저닝으로 변경 이력 관리 |

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

```javascript
import http from 'k6/http';
import { sleep } from 'k6';

export const options = { vus: 10, duration: '30s' };

export default function () {
  http.get('http://<ALB_DNS>/api/actuator/health');
  sleep(1);
}
```

부하 발생 시 Pod CPU/메모리/네트워크 트래픽이 대시보드에 실시간 반영되는 것을 확인해 파이프라인 정상 동작을 검증했습니다.

---

## 🔄 대시보드 개선 이력

운영하며 발견한 문제를 반복적으로 개선했다. (실시간 데이터 기준 점검 → 수정)

| 문제 발견 | 개선 |
|----------|------|
| 클러스터 게이지가 노드 오토스케일링으로 늘어나며 좁아짐 | 노드별 게이지로 전환, 폭 확대(w=12). 한 노드 과부하 감지 가능 |
| 죽은 노드의 게이지가 잠시 잔상으로 남음 | 게이지를 `avg by(instance)`로 유지하되 노드별 분리, staleness 후 자연 소거 |
| 게이지 라벨에 포트(`:9100`)가 붙어 지저분 | `label_replace`로 IP만 추출 |
| 파드 증가로 범례가 그래프를 잠식 | 범례를 우측 테이블로, 현재값·최대값 동시 표기 |
| IoT 쿼리 날짜 하드코딩(`day='10'`)으로 날짜 변경 시 빈 화면 | `$__timeFilter(timestamp)`로 동적화, 파티션 프로젝션 이점 유지 |

> 모니터링 대상(노드/파드)이 고정이 아니라 오토스케일링으로 변한다는 점을 고려해, "개수가 바뀌어도 레이아웃이 깨지지 않는" 시각화로 수렴시켰다.

---

## 📧 Grafana Alertmanager 이메일 알람

### 설계 목적
인프라 임계값 초과 시 관리자(bljh5220@gmail.com)에게 즉시 이메일 알람을 발송합니다.

### 구성

| 항목 | 값 |
|------|-----|
| SMTP 서버 | smtp.gmail.com:587 |
| 발신/수신 계정 | bljh5220@gmail.com |
| 인증 방식 | Gmail 앱 비밀번호 |
| TLS | 필수 |

### 알람 규칙 & 노이즈 억제

| alertname | 심각도 | 조건 |
|-----------|--------|------|
| PodFailed | critical | stockops Failed/ImagePullBackOff |
| PodRestartHigh | warning | 재시작 3회 초과 |
| NodeCPUHigh | critical | 노드 CPU 80% 초과 (3m) |
| NodeMemoryHigh | critical | 노드 메모리 85% 초과 (3m) |

> 기본 receiver를 `blackhole`로 두고 위 4개 알람만 `gmail`로 라우팅해 노이즈를 억제한다.

### 반복 알람 설정

| 항목 | 값 | 의미 |
|------|-----|------|
| group_wait | 30s | 첫 알람 대기 시간 |
| group_interval | 5m | 동일 그룹 재알람 간격 |
| repeat_interval | 12h | 미해결 알람 반복 간격 |