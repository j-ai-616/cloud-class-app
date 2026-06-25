# Python 3.12의 slim 이미지를 기반 이미지로 사용한다.
# slim은 기본 Python 이미지보다 용량이 작아 배포 이미지 크기를 줄일 수 있다.
FROM python:3.12-slim

# Python 실행 환경 옵션을 설정한다.
# PYTHONDONTWRITEBYTECODE=1
#   -> .pyc 캐시 파일을 만들지 않게 한다.
#   -> 컨테이너에서는 소스 캐시 파일이 꼭 필요하지 않으므로 불필요한 파일 생성을 줄인다.
#
# PYTHONUNBUFFERED=1
#   -> Python 출력 로그를 버퍼에 모아두지 않고 바로 출력한다.
#   -> docker logs에서 로그를 즉시 확인하기 좋다.
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

# 컨테이너 내부의 작업 디렉터리를 /app으로 설정한다.
# 이후 RUN, COPY, CMD 같은 명령은 기본적으로 /app을 기준으로 실행된다.
WORKDIR /app

# apt 패키지 목록을 갱신하고 curl을 설치한다.
# curl은 아래 HEALTHCHECK에서 /health/ URL을 호출하는 데 사용한다.
# --no-install-recommends는 필수 패키지만 설치해 이미지 크기를 줄이기 위한 옵션이다.
# rm -rf /var/lib/apt/lists/*는 apt 캐시를 삭제해 이미지 크기를 줄인다.
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*

# requirements.txt만 먼저 이미지에 복사한다.
# 패키지 목록이 바뀌지 않으면 Docker 빌드 캐시를 재사용할 수 있다.
COPY requirements.txt .

# requirements.txt에 기록된 Python 패키지를 설치한다.
# --no-cache-dir는 pip 다운로드 캐시를 남기지 않아 이미지 크기를 줄인다.
RUN pip install --no-cache-dir -r requirements.txt

# 컨테이너 안에서 애플리케이션을 실행할 전용 사용자를 만든다.
# root 사용자가 아닌 appuser로 실행해 보안 위험을 줄인다.
# uid 10001은 호스트의 일반 사용자 UID와 충돌 가능성을 낮추기 위해 지정한 값이다.
RUN useradd --create-home --uid 10001 appuser

# 현재 프로젝트 파일 전체를 컨테이너의 /app으로 복사한다.
# --chown=appuser:appuser는 복사된 파일의 소유자를 appuser로 지정한다.
# 그래야 이후 appuser 권한으로 파일을 읽고 실행할 수 있다.
COPY --chown=appuser:appuser . .

# 이후 명령과 컨테이너 실행 프로세스를 appuser 권한으로 실행한다.
# 운영 컨테이너를 root로 실행하지 않기 위한 설정이다.
USER appuser

# 컨테이너가 8000번 포트를 사용한다는 것을 문서화한다.
# EXPOSE만으로 포트가 외부에 열리지는 않는다.
# 실제 포트 연결은 docker run -p 옵션이나 compose.yml에서 설정한다.
EXPOSE 8000

# 컨테이너 상태 확인 명령을 정의한다.
# Docker가 주기적으로 /health/에 요청을 보내 애플리케이션이 정상 응답하는지 확인한다.
#
# --interval=30s
#   -> 30초마다 상태 확인을 실행한다.
# --timeout=3s
#   -> 3초 안에 응답하지 않으면 실패로 본다.
# --start-period=20s
#   -> 컨테이너 시작 후 20초 동안은 준비 시간으로 보고 실패를 바로 반영하지 않는다.
# --retries=3
#   -> 3번 연속 실패하면 unhealthy 상태로 판단한다.
#
# curl -fsS
#   -> 실패 시 에러를 반환하고, 성공 시 응답 본문을 조용히 처리한다.
# || exit 1
#   -> curl 요청이 실패하면 HEALTHCHECK도 실패로 처리한다.
HEALTHCHECK --interval=30s --timeout=3s --start-period=20s --retries=3 \
  CMD curl -fsS http://127.0.0.1:8000/health/ || exit 1

# 컨테이너가 시작될 때 실행할 기본 명령이다.
# Gunicorn으로 Django WSGI 애플리케이션을 실행한다.
#
# gunicorn
#   -> Python WSGI 애플리케이션 서버이다.
# --workers 2
#   -> 요청을 처리할 worker 프로세스를 2개 실행한다.
# --bind 0.0.0.0:8000
#   -> 컨테이너 내부의 모든 네트워크 인터페이스에서 8000번 포트를 연다.
#   -> 컨테이너 외부에서 포트 매핑으로 접근하려면 127.0.0.1이 아니라 0.0.0.0에 바인딩해야 한다.
# config.wsgi:application
#   -> config/wsgi.py 파일의 application 객체를 Gunicorn이 실행한다.
CMD ["gunicorn", "--workers", "2", "--bind", "0.0.0.0:8000", "config.wsgi:application"]