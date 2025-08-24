# Build argument for base image selection
ARG BASE_IMAGE=nvidia/cuda:12.4.1-cudnn-runtime-ubuntu22.04

# Stage 1: Base image with common dependencies
FROM ${BASE_IMAGE} AS base

# Build arguments for this stage (defaults provided by docker-bake.hcl)
ARG COMFYUI_VERSION=0.3.52
ARG CUDA_VERSION_FOR_COMFY
ARG ENABLE_PYTORCH_UPGRADE
ARG PYTORCH_INDEX_URL=

# Prevents prompts from packages asking for user input during installation
ENV DEBIAN_FRONTEND=noninteractive
# Prefer binary wheels over source distributions for faster pip installations
ENV PIP_PREFER_BINARY=1
# Ensures output from python is printed immediately to the terminal without buffering
ENV PYTHONUNBUFFERED=1
# Speed up some cmake builds
ENV CMAKE_BUILD_PARALLEL_LEVEL=8
ENV PIP_NO_CACHE_DIR=1

# Install Python, git and other necessary tools
RUN apt-get update && apt-get install -y \
    python3.11 \
    python3.11-venv \
    git \
    wget \
    libgl1 \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender1 \
    ffmpeg \
    && ln -sf /usr/bin/python3.11 /usr/bin/python \
    && ln -sf /usr/bin/pip3 /usr/bin/pip

# Clean up to reduce image size
RUN apt-get autoremove -y && apt-get clean -y && rm -rf /var/lib/apt/lists/*

# Install uv (latest) using official installer and create isolated venv
RUN wget -qO- https://astral.sh/uv/install.sh | sh \
    && ln -s /root/.local/bin/uv /usr/local/bin/uv \
    && ln -s /root/.local/bin/uvx /usr/local/bin/uvx \
    && uv venv /opt/venv

# Use the virtual environment for all subsequent commands
ENV PATH="/opt/venv/bin:${PATH}"

# Install comfy-cli + dependencies needed by it to install ComfyUI
RUN uv pip install comfy-cli pip setuptools wheel \
    && uv pip install "numpy<2" \
    && rm -rf /root/.cache/uv /root/.cache/pip

# Install ComfyUI
RUN /usr/bin/yes | comfy --workspace /comfyui install --version "${COMFYUI_VERSION}" --cuda-version "12.4.1" --nvidia

# Upgrade PyTorch if needed (for newer CUDA versions)
RUN uv pip install torch==2.4.0 torchvision==0.19.0 torchaudio==2.4.0 --index-url https://download.pytorch.org/whl/cu124

# Change working directory to ComfyUI
WORKDIR /comfyui

# Support for the network volume
ADD src/extra_model_paths.yaml ./

# Go back to the root
WORKDIR /

# Install Python runtime dependencies for the handler
RUN uv pip install runpod requests websocket-client \
    && rm -rf /root/.cache/uv /root/.cache/pip

# Copy and install common dependencies for custom nodes
COPY requirements-custom-nodes.txt /tmp/requirements-custom-nodes.txt
RUN uv pip install -r /tmp/requirements-custom-nodes.txt \
    && rm -rf /root/.cache/uv /root/.cache/pip \
    && find /opt/venv -type d -name '__pycache__' -prune -exec rm -rf {} +

# Add application code and scripts
ADD src/start.sh handler.py test_input.json ./
RUN chmod +x /start.sh

# Prevent pip from asking for confirmation during uninstall steps in custom nodes
ENV PIP_NO_INPUT=1

# Copy helper script to switch Manager network mode at container start
COPY scripts/comfy-manager-set-mode.sh /usr/local/bin/comfy-manager-set-mode
RUN chmod +x /usr/local/bin/comfy-manager-set-mode

# Set the default command to run when starting the container
CMD ["/start.sh"]

# Stage 3: Final image
FROM base AS final
