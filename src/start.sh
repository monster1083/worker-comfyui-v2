#!/usr/bin/env bash 

# ─────────────────────────────────────────────────────────────
# Copy all custom_nodes from network volume to local directory
if [ -d "/runpod-volume/ComfyUI/custom_nodes" ]; then
    echo "ls -la /runpod-volume/ComfyUI/custom_nodes"
    ls -la /runpod-volume/ComfyUI/custom_nodes/
    
    # Remove any existing symlinks or directories that might conflict
    rm -rf /comfyui/custom_nodes/custom_nodes
    
    # Copy all custom nodes
    cp -r /runpod-volume/ComfyUI/custom_nodes/* /comfyui/custom_nodes/ 2>/dev/null || echo "worker-comfyui: No files to copy or copy failed"
    
    echo "worker-comfyui: Custom nodes copied successfully"
    echo "ls -la /comfyui/custom_nodes/"
    ls -la /comfyui/custom_nodes/
else
    echo "worker-comfyui: No custom_nodes directory found in Network Volume"
fi


# Check if /runpod-volume/ComfyUI/models/insightface is mounted
if [ -d " /runpod-volume/ComfyUI/models/insightface" ]; then
    echo "/runpod-volume/ComfyUI/models/insightface directory exists." 
    
    # Create a soft link to /comfyi/models/insightface if it doesn't already exist 목적지에 없으면,
    if [ ! -L "/comfyui/models/insightface" ]; then
        ln -s /runpod-volume/ComfyUI/models/insightface /comfyi/models/insightface 
        echo "Created a soft link to /comfyi/models/insightface."
    else
        echo "Soft link already exists."
    fi 
else
    echo "/runpod-volume/ComfyUI/models/insightface directory does not exist."
fi


# Link output directory
echo "worker-comfyui: Linking output directory..."
ln -sf /runpod-volume/ComfyUI/output /comfyui/output

echo "worker-comfyui: Verifying setup..."
echo "/comfyui/custom_nodes/."
ls -la /comfyui/custom_nodes/ || echo "ERROR: /comfyui/custom_nodes directory check failed"
echo "/comfyui/output"
ls -la /comfyui/output || echo "ERROR: /comfyui/output link failed"
# ─────────────────────────────────────────────────────────────

# Use libtcmalloc for better memory management
TCMALLOC="$(ldconfig -p | grep -Po "libtcmalloc.so.\d" | head -n 1)"
export LD_PRELOAD="${TCMALLOC}"

# Ensure ComfyUI-Manager runs in offline network mode inside the container
comfy-manager-set-mode offline || echo "worker-comfyui - Could not set ComfyUI-Manager network_mode" >&2

echo "worker-comfyui: Starting ComfyUI"

# Allow operators to tweak verbosity; default is DEBUG.
: "${COMFY_LOG_LEVEL:=DEBUG}"

# Serve the API and don't shutdown the container
if [ "$SERVE_API_LOCALLY" == "true" ]; then
    python -u /comfyui/main.py --disable-auto-launch --disable-metadata --listen --verbose "${COMFY_LOG_LEVEL}" --log-stdout &

    echo "worker-comfyui: Starting RunPod Handler"
    python -u /handler.py --rp_serve_api --rp_api_host=0.0.0.0
else
    python -u /comfyui/main.py --disable-auto-launch --disable-metadata --verbose "${COMFY_LOG_LEVEL}" --log-stdout &

    echo "worker-comfyui: Starting RunPod Handler"
    python -u /handler.py
fi