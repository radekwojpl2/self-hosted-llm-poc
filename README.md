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
main.bicep                       # infra
cloud-init.yaml                  # first-boot: disk, drivers, Tailscale, Ollama, model, Open WebUI
parameters.json                  # non-secret defaults
.github/workflows/deploy.yml     # provision
.github/workflows/deprovision.yml# teardown (type DELETE to confirm)
scripts/bootstrap-oidc.sh        # one-shot: OIDC app, role, federated creds, gh secrets
```

## One-time setup

### 1. Azure OIDC federated credentials (automated)
Run the bootstrap script **once**, locally, while logged into `az` with rights to
create app registrations and assign roles. It creates the AD app, a Contributor
role assignment (scoped to the RG by default), the GitHub OIDC federated
credentials, and — if `gh` is installed — sets the Azure GitHub secrets for you.

```bash
az login
REPO=<owner>/<repo> RG_NAME=ollama-rg LOCATION=westeurope \
  ./scripts/bootstrap-oidc.sh
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
| Secret | Purpose |
|---|---|
| `AZURE_CLIENT_ID` | OIDC app/client id |
| `AZURE_TENANT_ID` | Azure AD tenant |
| `AZURE_SUBSCRIPTION_ID` | Subscription |
| `AZURE_RG` | Resource group name |
| `AZURE_LOCATION` | e.g. `westeurope` |
| `SSH_PUB` | Your SSH public key |
| `TS_AUTHKEY` | Tailscale ephemeral auth key |
| `TS_API_KEY` | Tailscale API token (teardown) |
| `TS_TAILNET` | Tailnet name |

## Deploy
Push to `main` (touching tracked paths) or run the **deploy** workflow manually.

## Use it

**Browser (Open WebUI):** from any device on your tailnet, open
`https://ollama-vm.<your-tailnet>.ts.net` (or `http://ollama-vm:8080` if HTTPS
certs aren't enabled). First visit, create the admin account. Chats and settings
persist on the data disk.

**CLI / API:**
```bash
tailscale ssh azureuser@ollama-vm                 # shell access
OLLAMA_HOST=http://ollama-vm:11434 ollama run llama3.1:8b
# or hit the API:
curl http://ollama-vm:11434/api/generate -d '{"model":"llama3.1:8b","prompt":"hi"}'
```

> Lock Ollama's `11434` down with **Tailscale ACLs** — it binds to `0.0.0.0` on the
> host but is only reachable inside the tailnet (no public inbound).

## Tear down
Run the **deprovision** workflow and type `DELETE`. It removes the Tailscale node,
then deletes the whole resource group (VM, disks, network, IP — everything).

## Notes
- T4 region availability and Spot quota vary — pick a region (`AZURE_LOCATION`) that
  has `Standard_NC4as_T4_v3` Spot capacity and request quota if needed.
- First boot installs NVIDIA drivers; allow a few minutes before GPU inference works.
- Change the model via `ollamaModel` in `parameters.json`.
