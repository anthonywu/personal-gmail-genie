#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

load_env

ensure_service_account "$RUNTIME_SERVICE_ACCOUNT_ID" "gmail-genie Cloud Run job"
ensure_service_account "$SCHEDULER_SERVICE_ACCOUNT_ID" "gmail-genie Cloud Scheduler trigger"

log "Granting Secret Manager access to ${RUNTIME_SERVICE_ACCOUNT_EMAIL}"
gcloud projects add-iam-policy-binding "$GCP_PROJECT_ID" \
  --member="serviceAccount:${RUNTIME_SERVICE_ACCOUNT_EMAIL}" \
  --role="roles/secretmanager.secretAccessor" >/dev/null

log "Service account setup complete"
