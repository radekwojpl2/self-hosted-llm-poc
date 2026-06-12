#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# One-shot bootstrap: creates the Azure AD app + OIDC federated credentials
# GitHub Actions uses to authenticate, assigns Contributor, and (optionally)
# pushes the resulting IDs into the repo's GitHub secrets.
#
# Run this ONCE, locally, by someone who is already `az login`'d with rights
# to create app registrations and assign roles. It cannot run inside the
# pipeline because it creates the identity the pipeline authenticates with.
#
# Requires: az, and (for auto-setting secrets) gh authenticated to the repo.
# ---------------------------------------------------------------------------
set -euo pipefail

# ---- Config (override via env) --------------------------------------------
APP_NAME="${APP_NAME:-ollama-azure-gha}"
REPO="${REPO:?Set REPO=owner/name}"                 # e.g. myuser/ollama-azure
SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-$(az account show --query id -o tsv)}"
RG_NAME="${RG_NAME:-ollama-rg}"
LOCATION="${LOCATION:-westeurope}"
BRANCH="${BRANCH:-main}"
# Scope the role to the RG (least privilege) unless SCOPE_SUBSCRIPTION=1.
SCOPE_SUBSCRIPTION="${SCOPE_SUBSCRIPTION:-0}"
# Push results into GitHub secrets via gh CLI (needs gh auth). 1=yes 0=no.
SET_GH_SECRETS="${SET_GH_SECRETS:-1}"

echo ">> Subscription: $SUBSCRIPTION_ID"
echo ">> Repo:         $REPO"
echo ">> App name:     $APP_NAME"

# ---- 1. App registration + service principal ------------------------------
APP_ID=$(az ad app list --display-name "$APP_NAME" --query "[0].appId" -o tsv)
if [ -z "$APP_ID" ]; then
  APP_ID=$(az ad app create --display-name "$APP_NAME" --query appId -o tsv)
  echo ">> Created app $APP_ID"
else
  echo ">> Reusing existing app $APP_ID"
fi

# Ensure a service principal exists for the app.
az ad sp show --id "$APP_ID" >/dev/null 2>&1 || az ad sp create --id "$APP_ID" >/dev/null
SP_OBJECT_ID=$(az ad sp show --id "$APP_ID" --query id -o tsv)
TENANT_ID=$(az account show --query tenantId -o tsv)

# ---- 2. Role assignment (Contributor) -------------------------------------
if [ "$SCOPE_SUBSCRIPTION" = "1" ]; then
  SCOPE="/subscriptions/$SUBSCRIPTION_ID"
else
  # Create the RG first so we can scope to it.
  az group create --name "$RG_NAME" --location "$LOCATION" -o none
  SCOPE="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RG_NAME"
fi
echo ">> Assigning Contributor at: $SCOPE"
az role assignment create \
  --assignee-object-id "$SP_OBJECT_ID" \
  --assignee-principal-type ServicePrincipal \
  --role Contributor \
  --scope "$SCOPE" -o none || echo "   (role assignment may already exist)"

# ---- 3. Federated credentials (OIDC) --------------------------------------
add_fic () {
  local name="$1" subject="$2"
  # Skip if a credential with this subject already exists.
  if az ad app federated-credential list --id "$APP_ID" \
       --query "[?subject=='$subject'] | [0].id" -o tsv | grep -q .; then
    echo ">> FIC exists: $subject"
    return
  fi
  az ad app federated-credential create --id "$APP_ID" --parameters "{
    \"name\": \"$name\",
    \"issuer\": \"https://token.actions.githubusercontent.com\",
    \"subject\": \"$subject\",
    \"audiences\": [\"api://AzureADTokenExchange\"]
  }" -o none
  echo ">> Added FIC: $subject"
}

# Branch ref covers BOTH push-to-main and workflow_dispatch runs on that branch
# (both deploy.yml and deprovision.yml run from refs/heads/main).
add_fic "gha-branch-$BRANCH" "repo:$REPO:ref:refs/heads/$BRANCH"
# If you later gate deprovision behind a GitHub environment named 'prod',
# uncomment the next line and add `environment: prod` to that job.
# add_fic "gha-env-prod" "repo:$REPO:environment:prod"

echo
echo "================ OIDC bootstrap complete ================"
echo "AZURE_CLIENT_ID       = $APP_ID"
echo "AZURE_TENANT_ID       = $TENANT_ID"
echo "AZURE_SUBSCRIPTION_ID = $SUBSCRIPTION_ID"
echo "AZURE_RG              = $RG_NAME"
echo "AZURE_LOCATION        = $LOCATION"
echo "========================================================"

# ---- 4. Push to GitHub secrets (optional) ---------------------------------
if [ "$SET_GH_SECRETS" = "1" ] && command -v gh >/dev/null 2>&1; then
  echo ">> Setting GitHub secrets via gh..."
  gh secret set AZURE_CLIENT_ID       --repo "$REPO" --body "$APP_ID"
  gh secret set AZURE_TENANT_ID       --repo "$REPO" --body "$TENANT_ID"
  gh secret set AZURE_SUBSCRIPTION_ID --repo "$REPO" --body "$SUBSCRIPTION_ID"
  gh secret set AZURE_RG              --repo "$REPO" --body "$RG_NAME"
  gh secret set AZURE_LOCATION        --repo "$REPO" --body "$LOCATION"
  echo ">> Azure secrets set. Still need to set manually:"
  echo "   SSH_PUB, TS_AUTHKEY, TS_API_KEY, TS_TAILNET"
else
  echo ">> gh not used. Add the values above as GitHub repo secrets."
fi
