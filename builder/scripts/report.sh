#!/usr/bin/env bash
# usage: report.sh STATUS [message] [progress]
set -u

BACKEND_URL="$(printf '%s' "${BACKEND_URL:-}" | tr -d ' "'$'\r\n\t' | sed 's#/*$##')"
if [ -z "$BACKEND_URL" ]; then
  BACKEND_URL="https://web2apkandaab.lovable.app"
fi
BUILDER_SECRET="$(printf '%s' "${BUILDER_SECRET:-}" | tr -d ' "'$'\r\n\t')"

jq -n --arg id "$BUILD_ID" --arg s "$1" --arg m "${2:-}" --arg p "${3:-}" --arg r "${GITHUB_RUN_ID:-}" \
  '{build_id:$id,status:$s,github_run_id:$r} + (if $m=="" then {} else {error_message:$m} end) + (if $p=="" then {} else {progress:($p|tonumber)} end)' \
| curl -fsS -X POST "$BACKEND_URL/api/public/builder/status" \
  -H "content-type: application/json" \
  -H "x-builder-secret: $BUILDER_SECRET" \
  -d @- >/dev/null
