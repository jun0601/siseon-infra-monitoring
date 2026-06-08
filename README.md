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

## 📊 Grafana 대시보드 구성

<<<<<<< Updated upstream
```
Amazon EKS (seoul-cluster)
        ↓
kube-prometheus-stack (Helm)
├── Prometheus          → Pod/Node 메트릭 수집 (보존 7일)
├── Node Exporter       → 노드 시스템 메트릭 (DaemonSet)
├── kube-state-metrics  → 클러스터 이벤트/상태
└── Grafana             → 통합 대시보드 (NLB 외부 노출)
        ↓
Grafana 데이터소스
├── Prometheus   → 인프라 메트릭 (공식 템플릿 + 커스텀)
└── CloudWatch   → 애플리케이션 로그 (추후 연동)
        ↓
AWS NLB (internet-facing)
        ↓
외부 접속 (브라우저)
```
=======
| 구분 | 방식 | 대시보드 |
|------|------|---------|
| 공식 템플릿 | Grafana Community | Node Exporter Full (ID: 1860) |
| 공식 템플릿 | Grafana Community | Kubernetes Cluster (ID: 7249) |
| 공식 템플릿 | Grafana Community | Kubernetes Pod (ID: 6417) |
| 커스텀 | 직접 제작 | 🏭 StockOps 인프라 현황 |
>>>>>>> Stashed changes

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

<<<<<<< Updated upstream
## 📊 Grafana 대시보드 구성

| 구분 | 방식 | 대시보드 |
|------|------|---------|
| 공식 템플릿 | Grafana Community | Node Exporter Full (ID: 1860) |
| 공식 템플릿 | Grafana Community | Kubernetes Cluster (ID: 7249) |
| 공식 템플릿 | Grafana Community | Kubernetes Pod (ID: 6417) |
| 커스텀 | 직접 제작 | 🏭 StockOps 인프라 현황 |

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

---

=======
>>>>>>> Stashed changes
## 📁 디렉토리 구조

```
siseon-infra-monitoring/
├── main.tf              # kube-prometheus-stack Helm 배포 + 대시보드 provisioning
├── providers.tf         # AWS / Kubernetes / Helm Provider 설정
├── variables.tf         # 변수 정의
├── outputs.tf           # 출력값
├── terraform.tfvars     # 민감 변수 (git 제외)
├── .gitignore
├── README.md            # 프로젝트 개요 및 배포 방법
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

---

## 🚀 배포 방법

### 사전 요구사항
- Terraform >= 1.0
- AWS CLI + SSO 설정 (`aws configure sso --profile siseon`)
- EKS 클러스터 구성 완료 (`seoul-cluster`)
- kubectl, helm 설치

### 1. SSO 로그인 + kubeconfig 설정

```bash
aws sso login --profile siseon
aws eks update-kubeconfig --region ap-northeast-2 --name seoul-cluster --profile siseon
```

### 2. 배포

```bash
<<<<<<< Updated upstream
terraform init
terraform plan
terraform apply  # 약 10~15분 소요
=======
# 1. SSO 로그인
aws sso login --profile siseon

# 2. 초기화
terraform init

# 3. 플랜 확인
terraform plan

# 4. 배포 (약 10~15분 소요)
terraform apply
>>>>>>> Stashed changes
```

### 3. 배포 확인

```bash
# Pod 상태 확인
kubectl get pods -n monitoring -w

# Grafana LoadBalancer IP 확인
kubectl get svc -n monitoring kube-prometheus-stack-grafana
```

### 4. Grafana 접속

```
URL: http://<EXTERNAL-IP>
ID : admin
PW : terraform.tfvars 에 설정한 값
```

<<<<<<< Updated upstream
---

## 🧪 부하 테스트 (k6)

Grafana 대시보드의 CPU/메모리/네트워크 그래프 변화를 확인하기 위한 부하 테스트입니다.

### k6 설치
=======
### 재배포 시 주의사항
>>>>>>> Stashed changes

```bash
choco install k6 -y
```

### 테스트 스크립트 작성

```javascript
// load_test.js
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

### 실행

```bash
k6 run load_test.js
```

Grafana **🏭 StockOps 인프라 현황** 대시보드에서 실시간으로 CPU/메모리/네트워크 변화를 확인할 수 있습니다.

---

## 🗑️ 삭제

```bash
# 1. Helm release 먼저 삭제
helm uninstall kube-prometheus-stack -n monitoring

<<<<<<< Updated upstream
# 2. Terraform state 정리 (재배포 실패 시)
terraform state rm helm_release.kube_prometheus_stack

# 3. Terraform 리소스 삭제
=======
# Terraform state 정리
terraform state rm helm_release.kube_prometheus_stack

# 재배포
terraform apply
```

### 삭제

```bash
helm uninstall kube-prometheus-stack -n monitoring
>>>>>>> Stashed changes
terraform destroy
```

---

## 🔗 연관 레포지토리

| 레포 | 설명 |
|------|------|
| [siseon-security](https://github.com/jun0601/siseon-security) | CloudTrail 보안/감사 모니터링 |
| [siseon-infra-monitoring](https://github.com/jun0601/siseon-infra-monitoring) | EKS 인프라 모니터링 (현재) |
| [siseon-infra](https://github.com/jun0601/siseon-infra) | 팀 메인 인프라 (VPC, EKS, ALB, RDS) |

---

## ⚠️ 주의사항

- `terraform.tfvars` 는 Grafana 비밀번호 포함으로 **절대 커밋 금지** (`.gitignore` 처리됨)
- EKS 클러스터(`seoul-cluster`)가 먼저 배포되어 있어야 함
<<<<<<< Updated upstream
- 퍼블릭 서브넷에 `kubernetes.io/role/elb = 1` 태그 필수 (NLB 생성 조건)
- NLB 외부 노출을 위해 `internet-facing` annotation 필수
=======
- EKS 퍼블릭 서브넷에 `kubernetes.io/role/elb = 1` 태그 필수
>>>>>>> Stashed changes
- AWS CLI SSO 토큰 만료 시 `aws sso login --profile siseon` 으로 재로그인 필요
- kube-prometheus-stack 배포에 약 **10~15분** 소요
- 재배포 시 반드시 `helm uninstall` + `terraform state rm` 후 진행