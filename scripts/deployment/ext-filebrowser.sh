#!/usr/bin/env bash
set -euxo pipefail

mkdir -p /mnt/models/hyper-extract-input
mkdir -p /mnt/models/hyper-extract-output
mkdir -p /mnt/models/filebrowser-db
# Filebrowser runs as uid=1000 inside the container
chown 1000:1000 /mnt/models/hyper-extract-input /mnt/models/hyper-extract-output

docker run -d --restart always \
  --name filebrowser \
  -p 127.0.0.1:8081:80 \
  -v /mnt/models/filebrowser-db:/database \
  -v /mnt/models:/srv \
  filebrowser/filebrowser

# Wait for container to initialise then set static admin password
until docker exec filebrowser filebrowser users update admin --password 'admin' -d /database/filebrowser.db 2>/dev/null; do
  sleep 2
done

cat > /etc/systemd/system/tailscale-serve-filebrowser.service <<'EOF'
[Unit]
Description=Tailscale Serve for Filebrowser
After=tailscaled.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/bin/tailscale serve --bg --http=8082 http://127.0.0.1:8081
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now tailscale-serve-filebrowser
