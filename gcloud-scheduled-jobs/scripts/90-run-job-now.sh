#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

load_env

log "Executing Cloud Run job now: $CLOUD_RUN_JOB_NAME"
gcloud run jobs execute "$CLOUD_RUN_JOB_NAME" --region="$GCP_REGION" --wait
