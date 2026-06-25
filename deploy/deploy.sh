#!/usr/bin/env bash

# 스크립트 실행 중 오류를 엄격하게 처리한다.
#
# -E
#   -> ERR trap이 함수나 서브셸에서도 상속되게 한다.
#      현재 스크립트에는 trap이 없지만, 운영 스크립트에서 자주 같이 사용한다.
#
# -e
#   -> 명령이 실패하면 즉시 스크립트를 종료한다.
#
# -u
#   -> 정의되지 않은 변수를 사용하면 오류로 처리한다.
#
# -o pipefail
#   -> 파이프라인 중간 명령이 실패해도 전체 명령을 실패로 처리한다.
set -Eeuo pipefail

# 배포 관련 파일이 있는 EC2 내부 디렉터리이다.
# 이 디렉터리에는 compose.yml 같은 배포용 파일이 있어야 한다.
PROJECT_DIR=/home/ubuntu/cloud-class-deploy

# Django 운영 환경 변수가 들어 있는 파일이다.
# docker compose 실행 시 컨테이너에 주입할 환경 변수 파일로 사용한다.
ENV_FILE=/etc/cloud-class.env

# ECR과 EC2가 사용할 AWS 리전이다.
AWS_REGION=ap-northeast-2

# Amazon ECR 저장소 이름이다.
ECR_REPOSITORY=cloud-class-app

# 배포할 이미지 태그이다.
# GitHub Actions에서 IMAGE_TAG=<커밋 SHA> 형태로 넘겨주면 그 값을 사용한다.
# 값이 없으면 latest 태그를 사용한다.
IMAGE_TAG=${IMAGE_TAG:-latest}

# 현재 EC2 IAM Role 기준으로 AWS 계정 ID를 조회한다.
# 예: 123456789012
AWS_ACCOUNT_ID=$(aws sts get-caller-identity \
  --query Account \
  --output text)

# ECR 레지스트리 주소를 만든다.
# 예: 123456789012.dkr.ecr.ap-northeast-2.amazonaws.com
ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

# Docker Compose에서 사용할 애플리케이션 이미지 전체 이름을 환경 변수로 내보낸다.
# 예: 123456789012.dkr.ecr.ap-northeast-2.amazonaws.com/cloud-class-app:커밋SHA
export APP_IMAGE="${ECR_REGISTRY}/${ECR_REPOSITORY}:${IMAGE_TAG}"

# Docker Compose에서 사용할 환경 변수 파일 경로를 환경 변수로 내보낸다.
export APP_ENV_FILE="${ENV_FILE}"

# 기존 환경 변수 파일에 APP_VERSION 값이 있으면 삭제한다.
# 같은 키가 여러 번 누적되지 않게 하기 위한 처리이다.
sudo sed -i '/^APP_VERSION=/d' "${ENV_FILE}"

# 현재 배포 버전을 환경 변수 파일에 기록한다.
# Django의 /api/info/ 같은 곳에서 현재 배포 버전을 보여줄 때 사용할 수 있다.
echo "APP_VERSION=${IMAGE_TAG}" | sudo tee -a "${ENV_FILE}" > /dev/null

# APP_ENV 값이 아직 없으면 aws로 추가한다.
# 이미 있으면 기존 값을 유지한다.
if ! grep -q '^APP_ENV=' "${ENV_FILE}"; then
  echo 'APP_ENV=aws' | sudo tee -a "${ENV_FILE}" > /dev/null
fi

# 배포용 compose.yml이 있는 디렉터리로 이동한다.
cd "${PROJECT_DIR}"

# ECR 로그인 토큰을 받아 Docker에 로그인한다.
# EC2 IAM Role 권한을 사용하므로 Access Key를 직접 저장하지 않는다.
aws ecr get-login-password --region "${AWS_REGION}" \
  | docker login \
      --username AWS \
      --password-stdin "${ECR_REGISTRY}"

# compose.yml의 web 서비스가 사용할 이미지를 ECR에서 내려받는다.
docker compose pull web

# 새 이미지로 Django 설정 검사를 실행한다.
# 설정 오류가 있으면 실제 서비스 교체 전에 배포를 중단한다.
docker compose run --rm web python manage.py check

# 새 이미지로 DB 마이그레이션을 실행한다.
# --noinput은 사용자 입력 없이 자동으로 진행하게 한다.
docker compose run --rm web python manage.py migrate --noinput

# 새 이미지로 web 서비스를 백그라운드에서 실행한다.
#
# --no-build
#   -> EC2에서 이미지를 다시 빌드하지 않는다.
#      ECR에서 받은 이미지만 사용한다.
#
# --remove-orphans
#   -> 현재 compose.yml에 없는 이전 서비스 컨테이너가 있으면 제거한다.
#
# web
#   -> web 서비스만 대상으로 실행한다.
docker compose up -d --no-build --remove-orphans web

# 현재 Docker Compose 서비스 상태를 출력한다.
docker compose ps

# Nginx를 거친 /health/ URL이 정상 응답할 때까지 최대 20번 확인한다.
# 한 번 실패할 때마다 3초씩 기다리므로 최대 약 60초까지 기다린다.
for attempt in $(seq 1 20); do
  if curl -fsS http://127.0.0.1/health/ > /dev/null; then
    break
  fi
  echo "waiting for application: attempt ${attempt}/20"
  sleep 3
done

# 최종적으로 주요 URL들이 정상 응답하는지 확인한다.
# 하나라도 실패하면 set -e 때문에 스크립트가 실패로 종료된다.

# 메인 화면이 응답하는지 확인한다.
curl -fsS http://127.0.0.1/ > /dev/null

# 상태 확인 API가 응답하는지 확인한다.
curl -fsS http://127.0.0.1/health/

# 애플리케이션 정보 API가 응답하는지 확인한다.
curl -fsS http://127.0.0.1/api/info/

# 여기까지 도달했다면 배포가 성공한 것이다.
# 실제 배포된 이미지 이름을 출력한다.
echo "deployment passed: ${APP_IMAGE}"
