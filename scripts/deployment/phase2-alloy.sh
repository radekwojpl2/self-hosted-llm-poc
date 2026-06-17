#!/usr/bin/env bash
# Credentials are written by the workflow step before this script runs.
# Expects /etc/alloy/credentials.env to already exist on the VM.
set -euxo pipefail

curl -fsSL https://apt.grafana.com/gpg.key \
  | gpg --dearmor -o /etc/apt/keyrings/grafana.gpg
echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" \
  > /etc/apt/sources.list.d/grafana.list
apt-get update -qq
apt-get install -y alloy

# Write config after install so the package cannot overwrite it.
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
