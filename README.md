# 📊 Siseon Infra Monitoring

> **StockOps ERP** 하이브리드 멀티클라우드 프로젝트의 인프라 모니터링 구성  
> Amazon EKS 클러스터의 Pod/Node 메트릭을 Prometheus로 수집하고 Grafana로 시각화하는 모니터링 스택을 Terraform + Helm으로 구현

---

## 📌 프로젝트 개요

| 항목 | 내용 |
|------|------|
| 프로젝트명 | StockOps ERP - 인프라 모니터링 파트 |
| 팀명 | 시선 (SISEON) |
| 담당 | 이준형 - 로그/모니터링 & 보안 파트 |
| 클라우드 | AWS (ap-northeast-2) |
| 대상 클러스터 | `seoul-cluster` (Amazon EKS) |
| IaC | Terraform + Helm |

---

## 🏗️ 전체 아키텍처

```
Amazon EKS (seoul-cluster)
        ↓
kube-prometheus-stack (Helm)
├── Prometheus          → Pod/Node 메트릭 수집 (보존 7일)
├── Node Exporter       → 노드 시스템 메트릭 (DaemonSet)
├── kube-state-metrics  → 클러스터 이벤트/상태
├── Grafana             → 통합 대시보드 (NLB 외부 노출)
└── Alertmanager        → 임계값 초과 시 Gmail 이메일 알람
        ↓
Grafana 데이터소스
├── Prometheus   → 인프라 메트릭 (공식 템플릿 + 커스텀)
└── CloudWatch   → 애플리케이션 로그 (추후 연동)
        ↓
AWS NLB (internet-facing)
        ↓
외부 접속 (브라우저)
```

---

## 📡 수집 메트릭

| 수집 대상 | 수집 도구 | 설명 |
|----------|----------|------|
| Pod CPU/메모리 사용률 | Prometheus | 컨테이너 리소스 현황 |
| Pod 재시작 횟수 | kube-state-metrics | CrashLoopBackOff 감지 |
| Node 상태 | Node Exporter | 워커 노드 헬스 체크 |
| 클러스터 이벤트 | kube-state-metrics | Deployment/Service 상태 |
| 네트워크 트래픽 | Prometheus | In/Out 바이트 |

---

## 📊 Grafana 대시보드 구성

| 구분 | 방식 | 대시보드 |
|------|------|---------|
| 공식 템플릿 | Grafana Community | Node Exporter Full (ID: 1860) |
| 공식 템플릿 | Grafana Community | Kubernetes Cluster (ID: 7249) |
| 공식 템플릿 | Grafana Community | Kubernetes Pod (ID: 6417) |
| 커스텀 | 직접 제작 | 🏭 StockOps 인프라 현황 |
| 커스텀 | 직접 제작 | 📈 StockOps 애플리케이션 메트릭 (api + 🤖 ai) |
| 커스텀 | 직접 제작 | 🛡️ StockOps WAF 보안 로그 (CloudWatch / 서울·오하이오·CloudFront) |

### 🏭 StockOps 인프라 현황 커스텀 대시보드 구성

| 패널 | 타입 | 설명 |
|------|------|------|
| 🖥️ 클러스터 CPU 사용률 | Gauge | 전체 노드 평균 CPU |
| 💾 클러스터 메모리 사용률 | Gauge | 전체 노드 평균 메모리 |
| ✅ Running Pods | Stat | 정상 실행 Pod 수 |
| 🚨 Failed Pods | Stat | 실패 Pod 수 |
| 🖧 Node 수 | Stat | 워커 노드 수 |
| ⏳ Pending Pods | Stat | 대기 중 Pod 수 |
| 📋 서비스별 Pod 상태 | Table | stockops 네임스페이스 Pod 현황 |
| ⚡ Pod CPU 사용률 | Timeseries | 서비스별 CPU 시계열 |
| 💡 Pod 메모리 사용량 | Timeseries | 서비스별 메모리 시계열 |
| 📥 네트워크 수신 | Timeseries | 인바운드 트래픽 |
| 📤 네트워크 송신 | Timeseries | 아웃바운드 트래픽 |
| 🔄 Pod 재시작 횟수 | Table | CrashLoopBackOff 감지 |
| 🟢 Node 상태 | Table | 노드 Ready 상태 |

### 📈 StockOps 애플리케이션 메트릭 커스텀 대시보드 구성

Spring Boot api-server(`/actuator/prometheus`)와 FastAPI ai-module(`/metrics`)이 노출하는 애플리케이션 메트릭을 각각 ServiceMonitor로 수집해 시각화합니다.

**api 패널 (6종)**

| 패널 | 타입 | 설명 |
|------|------|------|
| 🚀 API 처리량 (req/s) | Timeseries | HTTP 메서드별 초당 요청 수 |
| ❌ 에러율 (%) | Timeseries | 전체 요청 중 5xx 비율 |
| ⏱️ 평균 응답시간 | Timeseries | URI별 평균 처리 시간 |
| 🧠 JVM 힙 메모리 | Timeseries | 사용/할당 힙 메모리 |
| 🗄️ DB 커넥션 풀 (HikariCP) | Timeseries | 활성/유휴/대기 커넥션 |
| 🔌 Bedrock 회로차단기 상태 | Stat | resilience4j 회로차단기 (정상/차단) |

**🤖 ai 패널 (4종)**

| 패널 | 타입 | 설명 |
|------|------|------|
| 🤖 AI 예측 처리량 (req/s) | Timeseries | 초당 예측 요청 수 |
| 🤖 AI 예측 지연 p95 | Timeseries | 예측 소요 시간 (histogram → 진짜 p95) |
| 🤖 모델 캐시 적중률 (%) | Timeseries | prophet 모델 캐시 hit/miss 비율 |
| 🤖 예측 정확도 (MAPE %) | Timeseries | 실측 대비 예측 오차 (평가 데이터 축적 시 표시) |

> **메트릭 = api + ai 양쪽**: 초기엔 ai에 `/metrics`가 없어 추적(OpenTelemetry)으로만 관측하고 메트릭은 api 전용이었으나, 앱 업데이트로 ai-module에 `prometheus-fastapi-instrumentator`가 추가되며 `/metrics`가 생겨 ServiceMonitor를 부활시켰다. 이제 **메트릭·추적 모두 api+ai 양쪽**을 관측한다.
> Spring(api) 메트릭은 summary 타입이라 진짜 분위수(p95)는 불가, 평균(`_sum/_count`)으로 응답시간을 계산한다. 반면 FastAPI(ai) 메트릭은 histogram 타입이라 진짜 p95를 산출할 수 있다.
> 에러율·회로차단기는 정상 상태에서 0으로 표시되며, `or vector(0)`로 No data 대신 0%를 표기한다. ai 캐시 적중률은 누적 hit/miss 비율(`sum(hit)/sum(total)`)로 계산해 idle 구간에도 값이 유지되게 했다.

### ServiceMonitor (앱 메트릭 수집)

ServiceMonitor 커스텀 리소스로 Prometheus가 stockops 네임스페이스의 api Service를 스크랩하게 한다.

| 항목 | 값 |
|------|-----|
| 대상 | `stockops-api-svc` (stockops 네임스페이스) |
| 경로 | `/actuator/prometheus` |
| 포트 | 8080 (targetPort) |
| 라벨 | `release: kube-prometheus-stack` (Prometheus가 인식하는 셀렉터) |

> ServiceMonitor가 Service를 찾으려면 Service 메타데이터에 `app` 라벨이 있어야 한다. (트러블슈팅 #11 참고)

---

## 📧 Alertmanager 이메일 알람

인프라 임계값 초과 시 관리자에게 Gmail로 즉시 알람을 발송합니다.

| 항목 | 값 |
|------|-----|
| SMTP 서버 | smtp.gmail.com:587 |
| 발신/수신 | bljh5220@gmail.com |
| 인증 방식 | Gmail 앱 비밀번호 |
| repeat_interval | 12h (미해결 알람 반복) |

---

## 📁 디렉토리 구조

```
siseon-infra-monitoring/
├── main.tf              # kube-prometheus-stack Helm 배포 + 대시보드 provisioning
├── servicemonitor.tf    # 앱 메트릭 수집 ServiceMonitor (api)
├── providers.tf         # AWS / Kubernetes / Helm Provider 설정
├── variables.tf         # 변수 정의
├── outputs.tf           # 출력값
├── terraform.tfvars     # 민감 변수 (git 제외)
├── .gitignore
├── README.md
├── MONITORING.md        # 모니터링 설계 문서
└── TROUBLESHOOTING.md   # 트러블슈팅 기록
```

---

## 🛠️ 기술 스택

| 분류 | 기술 |
|------|------|
| IaC | Terraform >= 1.0 |
| 클러스터 | Amazon EKS (t3.medium x 2) |
| 모니터링 스택 | kube-prometheus-stack v58.0.0 |
| 메트릭 수집 | Prometheus + Node Exporter + kube-state-metrics |
| 시각화 | Grafana v10.4.0 |
| 로드밸런서 | AWS NLB (internet-facing) |
| 배포 방식 | Helm (Terraform Helm Provider) |
| 알림 | Gmail SMTP (Alertmanager) |

---

## 🚀 배포 방법

### 사전 요구사항
- Terraform >= 1.0
- AWS CLI + SSO 설정 (`aws configure sso --profile siseon`)
- EKS 클러스터 구성 완료 (`seoul-cluster`)
- kubectl, helm 설치

### terraform.tfvars 설정

```hcl
grafana_admin_password = "설정한 비밀번호"
gmail_app_password     = "Gmail 앱 비밀번호 16자리"
```

### 배포

```bash
aws sso login --profile siseon
aws eks update-kubeconfig --region ap-northeast-2 --name seoul-cluster --profile siseon
terraform init
terraform plan
terraform apply
```

### 배포 확인

```bash
kubectl get pods -n monitoring -w
kubectl get svc -n monitoring kube-prometheus-stack-grafana
```

### Grafana 접속

```
URL: https://grafana.siseon.live
ID : admin
PW : terraform.tfvars 에 설정한 값
```

> Grafana는 ALB Ingress(AWS Load Balancer Controller) + ACM 와일드카드 인증서(`*.siseon.live`)로 HTTPS 노출한다. 기존 NLB(http) 방식에서 전환했으며, Route 53 alias 레코드(`grafana.siseon.live` → ALB)를 Terraform이 직접 관리한다. (진우 인프라의 ACM ARN·Route 53 zone_id를 `terraform_remote_state`로 읽기만 함)

---

## 🧪 부하 테스트 (k6)

Grafana 대시보드의 실시간 메트릭 변화를 검증하기 위해 k6 부하 테스트를 수행했습니다.

### k6 설치
```bash
winget install k6 --source winget
```

### 테스트 스크립트 생성 (PowerShell)
```powershell
@"
import http from 'k6/http';
import { sleep } from 'k6';

export const options = { vus: 10, duration: '30s' };

export default function () {
  http.get('http://<ALB_DNS>/api/actuator/health');
  sleep(1);
}
"@ | Out-File load_test.js -Encoding utf8
k6 run load_test.js
```

### 테스트 결과
- **⚡ Pod CPU 사용률**: 부하 발생 시 급격한 상승 확인
- **💡 Pod 메모리 사용량**: 트래픽 증가에 따른 메모리 변화 확인
- **📥📤 네트워크 트래픽**: 요청/응답 트래픽 실시간 시각화 확인

---

### 🚨 Alert Rules

| 알람 | 조건 | 심각도 |
|------|------|--------|
| 🔴 PodFailed | stockops Failed/ImagePullBackOff Pod 발생 | critical |
| 🟡 PodRestartHigh | Pod 재시작 3회 초과 | warning |
| 🔴 NodeCPUHigh | 노드별 CPU 80% 초과 3분 지속 | critical |
| 🔴 NodeMemoryHigh | 노드별 메모리 85% 초과 3분 지속 | critical |

노이즈 알람 억제: EKS 컨트롤 플레인 관련 기본 알람(KubeSchedulerDown 등)은 blackhole receiver로 무시

---

## 📚 문서

- [MONITORING.md](./MONITORING.md) - 모니터링 설계 문서
- [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) - 트러블슈팅 기록

---

## 🔗 연관 레포지토리

| 레포 | 설명 |
|------|------|
| [siseon-security](https://github.com/jun0601/siseon-security) | CloudTrail 보안/감사 모니터링 |
| [siseon-infra-monitoring](https://github.com/jun0601/siseon-infra-monitoring) | EKS 인프라 모니터링 (현재) |
| [siseon-infra](https://github.com/jun0601/siseon-infra) | 팀 메인 인프라 (VPC, EKS, ALB, RDS) |

---

## ⚠️ 주의사항

- `terraform.tfvars`는 Grafana 비밀번호 + Gmail 앱 비밀번호 포함으로 **절대 커밋 금지** (`.gitignore` 처리됨)
- Alertmanager Gmail SMTP는 Google 앱 비밀번호 필수 (2단계 인증 활성화 후 생성)
- EKS 클러스터(`seoul-cluster`)가 먼저 배포되어 있어야 함
- 퍼블릭 서브넷에 `kubernetes.io/role/elb = 1` 태그 필수 (NLB 생성 조건)
- NLB 외부 노출을 위해 `internet-facing` annotation 필수
- AWS CLI SSO 토큰 만료 시 `aws sso login --profile siseon` 으로 재로그인 필요
- kube-prometheus-stack 배포에 약 **10~15분** 소요
- 재배포 시 반드시 `helm uninstall` + `terraform state rm` 후 진행