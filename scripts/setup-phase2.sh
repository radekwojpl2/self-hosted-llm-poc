#!/usr/bin/env bash
set -euxo pipefail

curl -fsSL https://tailscale.com/install.sh | sh
tailscale up --ssh --authkey="{0}" --hostname="{1}" --accept-routes

curl -fsSL https://ollama.com/install.sh | sh
mkdir -p /mnt/models
chown -R ollama:ollama /mnt/models || true
systemctl daemon-reload
systemctl enable --now ollama

curl -fsSL https://get.docker.com | sh
systemctl enable --now docker

mkdir -p /mnt/models/open-webui
docker run -d --restart always \
  --name open-webui \
  -p 127.0.0.1:8080:8080 \
  -e OLLAMA_BASE_URL=http://host.docker.internal:11434 \
  --add-host host.docker.internal:host-gateway \
  -v /mnt/models/open-webui:/app/backend/data \
  ghcr.io/open-webui/open-webui:main

systemctl enable --now tailscale-serve
