#!/usr/bin/env bash
# $1 = Tailscale auth key, $2 = hostname
set -euxo pipefail

curl -fsSL https://tailscale.com/install.sh | sh
tailscale up --ssh --authkey="$1" --hostname="$2" --accept-routes
