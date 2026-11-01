#!/usr/bin/env sh
# mix deps.get with retries. repo.hex.pm fetches time out intermittently from
# the CI node (`:timeout`, then "Unknown package ... in lockfile"); fewer
# parallel fetches, a longer timeout and three attempts get past it.
set -u
export HEX_HTTP_CONCURRENCY=4 HEX_HTTP_TIMEOUT=120
attempt=1
while :; do
  mix deps.get "$@" && exit 0
  [ "$attempt" -ge 3 ] && exit 1
  echo "deps.get failed (attempt $attempt), retrying"
  attempt=$((attempt + 1))
  sleep 15
done
