#!/usr/bin/env bash
set -euxo pipefail
export HOME=/root

curl -LsSf https://astral.sh/uv/install.sh | UV_INSTALL_DIR=/usr/local/bin sh

UV_TOOL_BIN_DIR=/usr/local/bin uv tool install hyperextract

mkdir -p /mnt/models/hyper-extract-output
