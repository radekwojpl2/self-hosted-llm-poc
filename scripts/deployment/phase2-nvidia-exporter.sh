#!/usr/bin/env bash
set -euxo pipefail

curl -fsSL https://github.com/utkuozdemir/nvidia_gpu_exporter/releases/download/v1.4.1/nvidia_gpu_exporter_1.4.1_linux_x86_64.tar.gz \
  | tar -xz -C /tmp
mv /tmp/nvidia_gpu_exporter /usr/local/bin/nvidia_gpu_exporter
chmod +x /usr/local/bin/nvidia_gpu_exporter
systemctl enable --now nvidia-gpu-exporter
