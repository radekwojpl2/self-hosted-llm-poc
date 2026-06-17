#!/usr/bin/env bash
# $1 = Grafana Cloud Prometheus URL
# $2 = Grafana Cloud Prometheus user/instance ID
# $3 = Grafana Cloud API key
set -euxo pipefail

curl -fsSL https://apt.grafana.com/gpg.key \
  | gpg --dearmor -o /etc/apt/keyrings/grafana.gpg
echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" \
  > /etc/apt/sources.list.d/grafana.list
apt-get update -qq

# Write credentials before install so Alloy can start if apt auto-starts it.
mkdir -p /etc/alloy

cat > /etc/alloy/credentials.env << EOF
GRAFANA_CLOUD_PROM_URL=$1
GRAFANA_CLOUD_PROM_USER=$2
GRAFANA_CLOUD_API_KEY=$3
EOF
chmod 600 /etc/alloy/credentials.env

# Install after credentials exist; write config after install so package cannot overwrite it.
apt-get install -y alloy

cat > /etc/alloy/config.alloy << 'ALLOYEOF'
prometheus.exporter.unix "node" {}

prometheus.scrape "node" {
  targets    = prometheus.exporter.unix.node.targets
  forward_to = [prometheus.remote_write.grafana_cloud.receiver]
}

prometheus.scrape "nvidia_gpu" {
  targets = [{
    __address__ = "localhost:9835",
  }]
  forward_to = [prometheus.remote_write.grafana_cloud.receiver]
}

prometheus.remote_write "grafana_cloud" {
  endpoint {
    url = env("GRAFANA_CLOUD_PROM_URL")
    basic_auth {
      username = env("GRAFANA_CLOUD_PROM_USER")
      password = env("GRAFANA_CLOUD_API_KEY")
    }
  }
}
ALLOYEOF

systemctl daemon-reload
systemctl enable --now alloy
