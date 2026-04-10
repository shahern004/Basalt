#!/usr/bin/env bash
set -euo pipefail

# bootstrap-basalt-host.sh — Idempotent setup for the basalt-host WSL2 distro.
#
# Run once after: wsl --import basalt-host D:\WSL\basalt-host\ <rootfs.tar> --version 2
#
# This script uses apt repos (internet required on the dev box).
# Air-gap targets receive this pre-baked via: wsl --export basalt-host <tarball>

BASALT_ROOT=/opt/basalt
MODELS_DIR=$BASALT_ROOT/models
FORGEJO_DIR=/opt/dev/forgejo

echo ""
echo "=== Basalt Host Bootstrap ==="
echo ""

# -------------------------------------------------------------------
# 1. Enable systemd (required for Docker Engine service management)
# -------------------------------------------------------------------
if ! grep -q 'systemd=true' /etc/wsl.conf 2>/dev/null; then
    echo ">>> Enabling systemd in /etc/wsl.conf..."
    sudo tee -a /etc/wsl.conf > /dev/null <<'WSLCONF'

[boot]
systemd=true
WSLCONF
    echo ""
    echo "!!! systemd enabled. You MUST restart the distro before continuing:"
    echo "    From PowerShell: wsl --terminate basalt-host"
    echo "    Then:            wsl -d basalt-host"
    echo "    Then re-run:     ./scripts/bootstrap-basalt-host.sh"
    echo ""
    exit 0
fi

# Verify systemd is actually running
if [ "$(ps -p 1 -o comm=)" != "systemd" ]; then
    echo "!!! systemd is configured but not running as PID 1."
    echo "    Restart the distro: wsl --terminate basalt-host && wsl -d basalt-host"
    exit 1
fi

echo ">>> systemd: running"

# -------------------------------------------------------------------
# 2. Install Docker Engine
# -------------------------------------------------------------------
if ! command -v docker &>/dev/null; then
    echo ">>> Installing Docker Engine..."
    sudo apt-get update -qq
    sudo apt-get install -y -qq ca-certificates curl gnupg

    # Add Docker GPG key
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg

    # Add Docker repo
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
        | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    sudo apt-get update -qq
    sudo apt-get install -y -qq \
        docker-ce docker-ce-cli containerd.io \
        docker-buildx-plugin docker-compose-plugin

    # Add current user to docker group
    sudo usermod -aG docker "$USER"
    echo ">>> Docker installed. Group membership takes effect on next login."
else
    echo ">>> Docker: already installed ($(docker --version))"
fi

# Ensure Docker service is running
if ! systemctl is-active --quiet docker; then
    sudo systemctl enable --now docker
    echo ">>> Docker service started."
else
    echo ">>> Docker service: running"
fi

# -------------------------------------------------------------------
# 3. Install NVIDIA Container Toolkit
# -------------------------------------------------------------------
if ! dpkg -l nvidia-container-toolkit &>/dev/null 2>&1; then
    echo ">>> Installing NVIDIA Container Toolkit..."
    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
        | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

    curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
        | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
        | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list > /dev/null

    sudo apt-get update -qq
    sudo apt-get install -y -qq nvidia-container-toolkit
    sudo nvidia-ctk runtime configure --runtime=docker
    sudo systemctl restart docker
    echo ">>> NVIDIA Container Toolkit installed and Docker runtime configured."
else
    echo ">>> NVIDIA Container Toolkit: already installed"
fi

# -------------------------------------------------------------------
# 4. Create directory structure
# -------------------------------------------------------------------
echo ">>> Creating directory structure..."
sudo mkdir -p "$BASALT_ROOT" "$MODELS_DIR" "$FORGEJO_DIR"
sudo chown -R "$USER:$USER" "$BASALT_ROOT"
sudo chown -R "$USER:$USER" /opt/dev

echo "    $BASALT_ROOT/"
echo "    $MODELS_DIR/"
echo "    $FORGEJO_DIR/"

# -------------------------------------------------------------------
# 5. Create proxy network (idempotent)
# -------------------------------------------------------------------
if docker network ls --format '{{.Name}}' | grep -qx 'proxy'; then
    echo ">>> Docker network 'proxy': already exists"
else
    docker network create proxy
    echo ">>> Docker network 'proxy': created"
fi

# -------------------------------------------------------------------
# 6. Verify GPU passthrough
# -------------------------------------------------------------------
echo ">>> Verifying GPU passthrough..."
if docker run --rm --gpus all nvidia/cuda:12.6.3-base-ubuntu24.04 nvidia-smi > /dev/null 2>&1; then
    echo ">>> GPU passthrough: verified"
else
    echo "!!! GPU passthrough failed. Check:"
    echo "    - NVIDIA driver is installed on the Windows host"
    echo "    - WSL2 kernel supports GPU passthrough (wsl --update)"
    echo "    (Continuing — vLLM will fail at startup if GPU is unavailable)"
fi

# -------------------------------------------------------------------
# Done
# -------------------------------------------------------------------
echo ""
echo "=== Bootstrap Complete ==="
echo ""
echo "Next steps:"
echo "  1. Copy/clone the Basalt repo:"
echo "     cp -r /mnt/d/BASALT/Basalt-Architecture/basalt-stack-v1.0 $BASALT_ROOT/basalt-stack-v1.0"
echo ""
echo "  2. Copy model weights:"
echo "     cp -r /mnt/d/BASALT/models/gemma-4-26B-A4B-it-AWQ-4bit $MODELS_DIR/"
echo ""
echo "  3. Follow the deployment guide:"
echo "     $BASALT_ROOT/basalt-stack-v1.0/docs/guides/deployment-guide-wsl2.md"
echo ""
