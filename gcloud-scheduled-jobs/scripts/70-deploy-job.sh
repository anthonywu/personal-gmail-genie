#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

load_env

log "Deploying Cloud Run job: $CLOUD_RUN_JOB_NAME"
deploy_args=(
  --region="$GCP_REGION"
  --image="$IMAGE_URI"
  --service-account="$RUNTIME_SERVICE_ACCOUNT_EMAIL"
  --cpu="$CLOUD_RUN_JOB_CPU"
  --memory="$CLOUD_RUN_JOB_MEMORY"
  --tasks="$CLOUD_RUN_JOB_TASKS"
  --max-retries="$CLOUD_RUN_JOB_MAX_RETRIES"
  --task-timeout="$CLOUD_RUN_JOB_TASK_TIMEOUT"
  --command="/bin/sh"
  --args="-ceu,$STARTUP_COMMAND"
  --set-secrets="$SECRET_MOUNTS"
)

if [[ -n "$JOB_ENV_VARS" ]]; then
  deploy_args+=(--update-env-vars="$JOB_ENV_VARS")
fi

gcloud run jobs deploy "$CLOUD_RUN_JOB_NAME" "${deploy_args[@]}" >/dev/null

ensure_job_invoker_binding
log "Cloud Run job deployment complete"
