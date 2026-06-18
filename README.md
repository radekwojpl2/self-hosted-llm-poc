# Ollama on Azure (Spot GPU) — Bicep + GitHub Actions + Tailscale

Deploys Ollama on a **Spot** NVIDIA T4 VM. SSH is via **Tailscale** only (no public
port 22). Models live on a **persistent data disk** so Spot evictions / auto-shutdown
don't force a re-download. Teardown deletes the **entire resource group** (Option A).

## Cost optimizations baked in
- **Spot VM** (`priority: Spot`, `evictionPolicy: Deallocate`) — up to ~70-90% off.
- **Auto-shutdown** daily (Azure-native `DevTestLab/schedules`) — no idle GPU overnight.
- **StandardSSD** OS + data disks (not Premium).
- **Standard public IP** for outbound Tailscale bootstrap — cheaper than a NAT gateway
  for a single VM. No inbound rules are opened.
- **Persistent data disk** for `/mnt/models` so restarts re-attach instead of re-pulling.

> Spot trade-off: Azure can evict with ~30s notice. The VM deallocates (not deletes),
> the data disk persists, and it can be restarted later. Treat it as ephemeral compute.

## Repo layout
```
main.bicep                            # infra
cloud-init.yaml                       # first-boot: static file drops (systemd units, helper scripts)
parameters.json                       # non-secret defaults
.github/workflows/deploy.yml          # provision + full VM setup
.github/workflows/deprovision.yml     # teardown (type DELETE to confirm)
.github/workflows/pull-model.yml      # pull (and optionally create a context-size variant of) a model
.github/workflows/deploy-extensions.yml # install Filebrowser + hyper-extract on existing VM
.github/workflows/extract.yml         # run hyper-extract on a file already on the VM
scripts/
  bootstrap/bootstrap-oidc.sh         # one-shot: OIDC app, role, federated creds, gh secrets
  deployment/phase1.sh                # disk setup + NVIDIA drivers (run via az vm run-command)
  deployment/phase2-tailscale.sh      # Tailscale install + join tailnet
  deployment/phase2-ollama.sh         # Ollama install
  deployment/phase2-docker.sh         # Docker install
  deployment/phase2-webui.sh          # Open WebUI container + Tailscale Serve
  deployment/phase2-nvidia-exporter.sh# NVIDIA GPU Prometheus exporter
  deployment/phase2-alloy.sh          # Grafana Alloy install + config
  deployment/ext-filebrowser.sh       # Filebrowser container + Tailscale Serve (port 8443)
  deployment/ext-hyper-extract.sh     # uv + hyperextract install
  deployment/pull-model.sh            # pull a model + create a named context-size variant
  deployment/extract.sh               # run hyper-extract on a file (called by extract workflow)
```

## Prerequisites

**Local tools**
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) (`az`) — for the bootstrap script and manual Azure operations
- [GitHub CLI](https://cli.github.com/) (`gh`) — optional; lets the bootstrap script push secrets automatically
- [Tailscale](https://tailscale.com/download) client — required to SSH into the VM (no public port 22)

**Azure**
- Subscription with rights to create app registrations and assign the Contributor role
- Two quota increases in your chosen region (`Home → Subscriptions → Usage + quotas`):
  - **Standard NCSv3 Family vCPUs** (T4 VM family): 0 → 1
  - **Total Regional Spot vCPUs**: 3 → 16

**GitHub**
- A repository with Actions enabled

**Tailscale**
- An account with MagicDNS and HTTPS certificates enabled (Admin → DNS) so Tailscale Serve can expose Open WebUI over `https://`

## One-time setup

### 1. Azure OIDC federated credentials (automated)
Run the bootstrap script **once**, locally, while logged into `az` with rights to
create app registrations and assign roles. It creates the AD app, a Contributor
role assignment (scoped to the RG by default), the GitHub OIDC federated
credentials, and — if `gh` is installed — sets the Azure GitHub secrets for you.

```bash
az login
REPO=<owner>/<repo> RG_NAME=ollama-rg LOCATION=westeurope \
  ./scripts/bootstrap/bootstrap-oidc.sh
```

Useful overrides: `SCOPE_SUBSCRIPTION=1` (assign at subscription scope instead of
RG), `SET_GH_SECRETS=0` (print values instead of pushing to GitHub), `BRANCH=main`.
It's idempotent — safe to re-run. It cannot run inside the pipeline, since it
creates the very identity the pipeline authenticates with.

### 2. Tailscale keys
- **Auth key** (`TS_AUTHKEY`): reusable, **ephemeral**, **pre-authorized** — from
  Admin → Settings → Keys.
- **API access token** (`TS_API_KEY`): for node cleanup on teardown. An OAuth client
  with `devices` write scope is the durable option.
- **Tailnet** (`TS_TAILNET`): e.g. `your-org.ts.net`, or `-` for your default tailnet.
- **Enable HTTPS certificates** in the tailnet (Admin → DNS → enable MagicDNS +
  HTTPS) so Tailscale Serve can publish Open WebUI at a `https://...ts.net` URL.
  If left off, the UI still serves over plain HTTP on the tailnet.

### 3. GitHub secrets

Go to your repo → **Settings** → **Secrets and variables** → **Actions** → **New repository secret** for each one below.

**Azure** — populated automatically by `bootstrap-oidc.sh` if `gh` is installed, otherwise printed to stdout:

| Secret | Where to find it |
|---|---|
| `AZURE_CLIENT_ID` | Output of bootstrap script / Azure AD → App registrations |
| `AZURE_TENANT_ID` | Azure AD → Overview |
| `AZURE_SUBSCRIPTION_ID` | Azure portal → Subscriptions |
| `AZURE_RG` | Resource group name you want to deploy into |
| `AZURE_LOCATION` | Azure region e.g. `westeurope` |
| `SSH_PUB` | Your local public key — `cat ~/.ssh/id_rsa.pub` |

**Tailscale** — from [admin.tailscale.com](https://admin.tailscale.com):

| Secret | Where to find it |
|---|---|
| `TS_AUTHKEY` | Admin → Settings → Keys → **Generate auth key** (reusable, ephemeral, pre-authorized) |
| `TS_API_KEY` | Admin → Settings → **OAuth clients** → create with `devices:write` scope |
| `TS_TAILNET` | Admin → DNS → your tailnet name e.g. `your-org.ts.net` |

**Grafana Cloud** — from [grafana.com](https://grafana.com) → your stack:

| Secret | Where to find it |
|---|---|
| `GRAFANA_CLOUD_PROM_URL` | Connections → Data sources → your Prometheus → **Prometheus Server URL** — append `/push` |
| `GRAFANA_CLOUD_PROM_USER` | Same page → **Username / Instance ID** |
| `GRAFANA_CLOUD_API_KEY` | Search **Access Policies** → create with `metrics:write` scope → Add token |

## Deploy
Run the **deploy** workflow manually from GitHub Actions.

The pipeline drives the full VM setup end-to-end as discrete steps:
1. **Bicep deploy** — creates VM, data disk, networking
2. **Phase 1** — disk setup + NVIDIA drivers (~5–10 min)
3. **VM restart** — activates drivers
4. **Phase 2a–2f** — Tailscale, Ollama, Docker, Open WebUI, NVIDIA exporter, Grafana Alloy (~10 min)

When the workflow shows green, the VM is fully set up. Total: **~20–30 minutes**.

## VM scripts

The VM ships several helper commands (installed to `/usr/local/bin/`):

| Command | What it does |
|---|---|
| `start` | Creates a `vm` tmux session with 3 panes (see layout below). Run once after SSH. |
| `attach-start` | Re-attaches to the existing `vm` session after disconnect. |
| `deepseek-r1-32k-start` | Pulls `deepseek-r1:14b`, creates a `deepseek-r1-32k` variant with 32 k context, then runs it. Skip the pull if already downloaded. |
| `qwen14b-start` | Pulls `qwen2.5:14b`, creates a `qwen2.5-14b-20k` variant with 20 k context, then runs it. Skips the pull if already downloaded. |
| `qwen-start` | Pulls `qwen2.5:32b`, creates a `qwen2.5-32b-128k` variant with 128 k context, then runs it. Skips the pull if already downloaded. **Requires NC64as T4 v3 (64 GB VRAM).** |
| `qwen72b-start` | Pulls `qwen2.5:72b`, creates a `qwen2.5-72b-32k` variant with 32 k context, then runs it. Skips the pull if already downloaded. **Requires NC64as T4 v3 (64 GB VRAM).** |

### tmux layout (`start`)

**Window 0** — main shell:
```
+-------------------------------+
|                               |
|          your shell           |
|                               |
+---------------+---------------+
|  ollama logs  |  nvidia-smi   |
| (journalctl)  |  (watch -n1)  |
+---------------+---------------+
```

### tmux cheat sheet

| Key | Action |
|---|---|
| `Ctrl-b d` | Detach session (leaves everything running) |
| `Ctrl-b <arrow>` | Move focus between panes |
| `Ctrl-b 0` | Switch to window 0 (main shell) |
| `Ctrl-b z` | Zoom/unzoom the active pane |
| `Ctrl-b [` | Enter scroll/copy mode — use arrows or `PgUp`/`PgDn` to scroll, `q` to exit |
| `Ctrl-b q` | Flash pane numbers |
| `Ctrl-b x` | Kill active pane (confirm with `y`) |
| `Ctrl-b &` | Kill current window (confirm with `y`) |

To re-attach after SSH disconnect: run `attach-start` (or `tmux attach -t vm` directly).

## Pull a model

**Via GitHub Actions (recommended):** run the **pull-model** workflow manually from GitHub Actions. Select a model from the dropdown and, optionally, override the context size (leave `0` for the per-model default). The workflow SSHes into the VM via `az vm run-command`, pulls the model, and creates a named context-size variant automatically. Per-model defaults:

| Model | Default context | Variant name created |
|---|---|---|
| `qwen2.5:14b` | 20 k (20480) | `qwen2.5-14b-20k` |
| `qwen2.5:32b` | 128 k (131072) | `qwen2.5-32b-128k` |
| `qwen2.5:72b` | 32 k (32768) | `qwen2.5-72b-32k` |
| `deepseek-r1:14b` | 32 k (32768) | `deepseek-r1-32k` |

**Manually over SSH:** for any other model, SSH in and pull directly:

```bash
ssh azureuser@ollama-vm-1
ollama pull llama3.2:1b      # ~1.3 GB, smallest model with tool support
ollama pull llama3.2:3b      # ~2 GB, better quality
ollama pull llama3.1:8b      # ~4.7 GB, recommended for GPU
ollama list                  # verify downloaded models
```

For models with extended context, the bundled VM scripts pull, create a variant, and start the model in one step:

```bash
deepseek-r1-32k-start        # pulls deepseek-r1:14b, creates 32k-context variant, and runs it
qwen14b-start                # pulls qwen2.5:14b, creates 20k-context variant, and runs it
qwen-start                   # pulls qwen2.5:32b, creates 128k-context variant, and runs it (NC64as only)
qwen72b-start                # pulls qwen2.5:72b, creates 32k-context variant, and runs it (NC64as only)
```

Models are stored on the persistent data disk (`/mnt/models`) and survive VM restarts.

## Use it

**Browser (Open WebUI):** from any device on your tailnet, open
`https://ollama-vm-1.<your-tailnet>.ts.net`. First visit, create the admin account.
Chats and settings persist on the data disk.

> Ollama binds to `0.0.0.0:11434` but is only reachable inside the tailnet — no public inbound ports are open.

**opencode:** add this to your `~/.opencode/config.json` to use the VM as a provider:

```json
"ollama": {
  "npm": "@ai-sdk/openai-compatible",
  "name": "Ollama (VM)",
  "options": {
    "baseURL": "http://ollama-vm-1:11434/v1"
  },
  "models": {
    "deepseek-r1-32k": {
      "name": "DeepSeek R1 32k"
    },
    "qwen2.5-14b-20k": {
      "name": "Qwen2.5 14B 20k"
    },
    "qwen2.5-32b-128k": {
      "name": "Qwen2.5 32B 128k"
    },
    "qwen2.5-72b-32k": {
      "name": "Qwen2.5 72B 32k"
    }
  }
}
```

## Filebrowser

Browse and download hyper-extract output from any device on your tailnet:

```
https://ollama-vm-1.<your-tailnet>.ts.net:8443
```

Default credentials: `admin` / `admin` — **change on first login** (top-right → Settings → Password).

Files live on the persistent data disk at `/mnt/models/hyper-extract-output/` and survive VM restarts.

## Knowledge extraction (hyper-extract)

[hyper-extract](https://github.com/yifanfeng97/hyper-extract) transforms unstructured documents into structured knowledge graphs using the VM's Ollama models.

**Workflow:**

1. Upload your file to `hyper-extract-input/` via Filebrowser.
2. Trigger the **extract** workflow from GitHub Actions → fill in:
   - `file_path` — filename only (e.g. `paper.md`)
   - `template` — extraction template (e.g. `general/biography_graph`, `finance/earnings_graph`, `general/academic_graph`)
   - `model` — Ollama model to use
3. Output appears in Filebrowser under a timestamped folder: `<YYYYMMDD-HHMMSS>-<filename>/`

**Available templates (examples):**

| Template | Use case |
|---|---|
| `general/biography_graph` | People, organisations, events |
| `general/academic_graph` | Research papers, citations |
| `finance/earnings_graph` | Earnings reports, financials |

Run `he list templates` on the VM to see all 80+ templates.

## Grafana dashboards

Once Alloy is shipping metrics, import the pre-built community dashboards.

1. Grafana Cloud → **Dashboards** → **New** → **Import**
2. Enter the dashboard ID → **Load** → select your Prometheus data source → **Import**

| Dashboard | ID | What it shows |
|---|---|---|
| Node Exporter Full | `1860` | CPU, RAM, disk, network |
| NVIDIA GPU Metrics | `14574` | GPU utilisation, VRAM, temp, power |

## Tear down
Run the **deprovision** workflow and type `DELETE`. It removes the Tailscale node,
then deletes the whole resource group (VM, disks, network, IP — everything).

## Notes
- T4 region availability and Spot quota vary — pick a region (`AZURE_LOCATION`) that
  has `Standard_NC16as_T4_v3` Spot capacity and request quota if needed.
- First boot installs NVIDIA drivers via `ubuntu-drivers install`; allow a few extra minutes before GPU inference works.
- VM size, disk size, and auto-shutdown time can be adjusted in `parameters.json`.
