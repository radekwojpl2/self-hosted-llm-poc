#!/usr/bin/env bash
set -euxo pipefail

curl -fsSL https://get.docker.com | sh
systemctl enable --now docker
