
# Build argument for base image selection
ARG BASE_IMAGE=runpod/pytorch:2.4.0-py3.11-cuda12.4.1-devel-ubuntu22.04

# Stage 1: Base image with common dependencies
FROM ${BASE_IMAGE} AS builder

# Build arguments for this stage (defaults provided by docker-bake.hcl)
ARG COMFYUI_VERSION=latest

# Prevents prompts from packages asking for user input during installation
ENV DEBIAN_FRONTEND=noninteractive
# Prefer binary wheels over source distributions for faster pip installations
ENV PIP_PREFER_BINARY=1
# Ensures output from python is printed immediately to the terminal without buffering
ENV PYTHONUNBUFFERED=1
# Speed up some cmake builds
ENV CMAKE_BUILD_PARALLEL_LEVEL=8
ENV PIP_NO_CACHE_DIR=1

# uv를 먼저 설치
RUN pip install uv
# 가상 환경을 만들고 활성화
# RUN uv venv /opt/venv
RUN uv venv --system-site-packages /opt/venv
ENV PATH="/opt/venv/bin:${PATH}"

# comfy-cli와 기본 패키지를 먼저 설치
RUN uv pip install comfy-cli pip setuptools wheel
# 캐시 제거는 한 번만 수행
RUN rm -rf /root/.cache/uv /root/.cache/pip

# Install ComfyUI
RUN echo "PATH: $PATH" && \
    echo "COMFYUI_VERSION: ${COMFYUI_VERSION}" && \
    which comfy && \
    comfy --help

# comfy 설치
RUN /usr/bin/yes | /opt/venv/bin/comfy --workspace /comfyui install --version "${COMFYUI_VERSION}" || true 
RUN rm -rf /comfyui/.git /tmp/* /var/tmp/* /root/.cache/*

# Change working directory to ComfyUI
WORKDIR /comfyui

# Support for the network volume
ADD src/extra_model_paths.yaml ./

# Go back to the root
WORKDIR /

# Install Python runtime dependencies for the handler
RUN uv pip install runpod requests websocket-client \
    && rm -rf /root/.cache/uv /root/.cache/pip

RUN uv pip install "numpy<2.0"

# Copy and install common dependencies for custom nodes
COPY requirements-custom-nodes.txt /tmp/requirements-custom-nodes.txt
RUN uv pip install -r /tmp/requirements-custom-nodes.txt \
    && rm -rf /root/.cache/uv /root/.cache/pip \
    && find /opt/venv -type d -name '__pycache__' -prune -exec rm -rf {} +

# Add application code and scripts
ADD src/start.sh handler.py test_input.json ./
RUN chmod +x /start.sh

# Copy helper script to switch Manager network mode at container start
COPY scripts/comfy-manager-set-mode.sh /usr/local/bin/comfy-manager-set-mode
RUN chmod +x /usr/local/bin/comfy-manager-set-mode

# Prevent pip from asking for confirmation during uninstall steps in custom nodes
ENV PIP_NO_INPUT=1

# Builder 마지막에 추가
RUN rm -rf /usr/share/doc /usr/share/man /var/lib/apt/lists/* \
    && find /opt/venv -name "*.pyc" -delete \
    && find /opt/venv -name "*.pyo" -delete

# Set the default command to run when starting the container
# CMD ["/start.sh"]

# Stage 3: Final image
# FROM base AS final
FROM ${BASE_IMAGE} AS final

# 환경변수만 복사
ENV PATH="/opt/venv/bin:${PATH}"
ENV PIP_NO_INPUT=1

# 필수 항목들 복사
COPY --from=builder /opt/venv /opt/venv
COPY --from=builder /comfyui /comfyui
COPY --from=builder /start.sh /handler.py /test_input.json ./
COPY --from=builder /usr/local/bin/comfy-manager-set-mode /usr/local/bin/

# 실행 권한
RUN chmod +x /start.sh /handler.py /usr/local/bin/comfy-manager-set-mode

WORKDIR /
CMD ["/start.sh"]





