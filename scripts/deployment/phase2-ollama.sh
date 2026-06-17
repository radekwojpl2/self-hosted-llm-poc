#!/usr/bin/env bash
set -euxo pipefail

curl -fsSL https://ollama.com/install.sh | sh
mkdir -p /mnt/models
chown -R ollama:ollama /mnt/models || true
systemctl daemon-reload
systemctl enable --now ollama
