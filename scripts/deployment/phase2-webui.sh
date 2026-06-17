#!/usr/bin/env bash
set -euxo pipefail

mkdir -p /mnt/models/open-webui
docker run -d --restart always \
  --name open-webui \
  -p 127.0.0.1:8080:8080 \
  -e OLLAMA_BASE_URL=http://host.docker.internal:11434 \
  --add-host host.docker.internal:host-gateway \
  -v /mnt/models/open-webui:/app/backend/data \
  ghcr.io/open-webui/open-webui:latest

systemctl enable --now tailscale-serve
