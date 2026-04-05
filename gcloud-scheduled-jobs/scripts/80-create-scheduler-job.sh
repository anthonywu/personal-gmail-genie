#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

load_env

if scheduler_job_exists; then
  log "Updating Cloud Scheduler job: $SCHEDULER_JOB_NAME"
  gcloud scheduler jobs update http "$SCHEDULER_JOB_NAME" \
    --location="$GCP_SCHEDULER_REGION" \
    --schedule="$SCHEDULER_CRON" \
    --time-zone="$SCHEDULER_TIME_ZONE" \
    --uri="$JOB_RUN_URI" \
    --http-method=POST \
    --headers="Content-Type=application/json" \
    --message-body='{}' \
    --oauth-service-account-email="$SCHEDULER_SERVICE_ACCOUNT_EMAIL" \
    --oauth-token-scope="$SCHEDULER_OAUTH_TOKEN_SCOPE" >/dev/null
else
  log "Creating Cloud Scheduler job: $SCHEDULER_JOB_NAME"
  gcloud scheduler jobs create http "$SCHEDULER_JOB_NAME" \
    --location="$GCP_SCHEDULER_REGION" \
    --schedule="$SCHEDULER_CRON" \
    --time-zone="$SCHEDULER_TIME_ZONE" \
    --uri="$JOB_RUN_URI" \
    --http-method=POST \
    --headers="Content-Type=application/json" \
    --message-body='{}' \
    --oauth-service-account-email="$SCHEDULER_SERVICE_ACCOUNT_EMAIL" \
    --oauth-token-scope="$SCHEDULER_OAUTH_TOKEN_SCOPE" >/dev/null
fi

log "Cloud Scheduler configuration complete"
