#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

load_env

upsert_scheduler_job() {
  local job_name="$1"
  local schedule="$2"

  if scheduler_job_exists "$job_name"; then
    log "Updating Cloud Scheduler job: $job_name"
    gcloud scheduler jobs update http "$job_name" \
      --location="$GCP_SCHEDULER_REGION" \
      --schedule="$schedule" \
      --time-zone="$SCHEDULER_TIME_ZONE" \
      --uri="$JOB_RUN_URI" \
      --http-method=POST \
      --update-headers="Content-Type=application/json" \
      --message-body='{}' \
      --oauth-service-account-email="$SCHEDULER_SERVICE_ACCOUNT_EMAIL" \
      --oauth-token-scope="$SCHEDULER_OAUTH_TOKEN_SCOPE" >/dev/null
    return
  fi

  log "Creating Cloud Scheduler job: $job_name"
  gcloud scheduler jobs create http "$job_name" \
    --location="$GCP_SCHEDULER_REGION" \
    --schedule="$schedule" \
    --time-zone="$SCHEDULER_TIME_ZONE" \
    --uri="$JOB_RUN_URI" \
    --http-method=POST \
    --headers="Content-Type=application/json" \
    --message-body='{}' \
    --oauth-service-account-email="$SCHEDULER_SERVICE_ACCOUNT_EMAIL" \
    --oauth-token-scope="$SCHEDULER_OAUTH_TOKEN_SCOPE" >/dev/null
}

upsert_scheduler_job "$SCHEDULER_DAYTIME_JOB_NAME" "$SCHEDULER_DAYTIME_CRON"
upsert_scheduler_job "$SCHEDULER_OVERNIGHT_JOB_NAME" "$SCHEDULER_OVERNIGHT_CRON"

log "Cloud Scheduler configuration complete"
