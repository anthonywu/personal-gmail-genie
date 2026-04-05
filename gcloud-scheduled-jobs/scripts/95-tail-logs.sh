#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

load_env

log_filter="resource.type=cloud_run_job AND labels.\"run.googleapis.com/job_name\"=\"${CLOUD_RUN_JOB_NAME}\""

if "$GCLOUD_BIN" beta logging tail --help >/dev/null 2>&1; then
  log "Streaming logs for ${CLOUD_RUN_JOB_NAME}"
  gcloud beta logging tail "$log_filter"
else
  log "Showing the latest ${LOG_LIMIT} log entries for ${CLOUD_RUN_JOB_NAME}"
  gcloud logging read "$log_filter" \
    --limit="$LOG_LIMIT" \
    --order=desc \
    --format="table(timestamp,severity,textPayload,jsonPayload.message)"
fi
