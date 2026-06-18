#!/usr/bin/env bash
set -euxo pipefail

mkdir -p /mnt/models/hyper-extract-input
mkdir -p /mnt/models/hyper-extract-output

docker run -d --restart always \
  --name filebrowser \
  -p 127.0.0.1:8081:80 \
  -v /mnt/models/filebrowser.db:/database.db \
  -v /mnt/models:/srv \
  filebrowser/filebrowser

cat > /etc/systemd/system/tailscale-serve-filebrowser.service <<'EOF'
[Unit]
Description=Tailscale Serve for Filebrowser
After=tailscaled.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/bin/tailscale serve --bg --https=8443 http://127.0.0.1:8081
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now tailscale-serve-filebrowser
