#!/usr/bin/env bash
set -euxo pipefail
export HOME=/root

curl -LsSf https://astral.sh/uv/install.sh | UV_INSTALL_DIR=/usr/local/bin sh

UV_TOOL_BIN_DIR=/usr/local/bin uv tool install hyperextract

mkdir -p /mnt/models/hyper-extract-input
mkdir -p /mnt/models/hyper-extract-output

# Pull embedding model used by hyper-extract
ollama pull nomic-embed-text

# Pre-configure embedder so extract.sh doesn't need to do it each run
# (extract.sh also sets it explicitly for safety)
he config embedder \
  --provider vllm \
  --model nomic-embed-text \
  --api-key ollama \
  --base-url http://localhost:11434/v1
