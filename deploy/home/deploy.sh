#!/bin/sh
set -eu

deploy_dir=${WECHAT_AI_DEPLOY_DIR:-/opt/wechat-ai}
cd "$deploy_dir"

exec 9>"$deploy_dir/.deploy.lock"
if ! flock -n 9; then
  echo "[deploy] another update is running"
  exit 0
fi

image_ref=$(docker inspect --format '{{.Config.Image}}' wechat-ai 2>/dev/null || true)
old_id=$(docker inspect --format '{{.Image}}' wechat-ai 2>/dev/null || true)

if [ -z "$image_ref" ]; then
  echo "[deploy] wechat-ai container does not exist"
  exit 1
fi

docker compose pull wechat-ai
new_id=$(docker image inspect --format '{{.Id}}' "$image_ref")

if [ "$old_id" = "$new_id" ]; then
  echo "[deploy] already current: $new_id"
  exit 0
fi

echo "[deploy] updating $old_id -> $new_id"
docker compose up -d --no-deps wechat-ai

attempt=0
while [ "$attempt" -lt 30 ]; do
  if curl -fsS --max-time 5 http://10.16.6.15:8787/health/ready >/dev/null; then
    echo "[deploy] healthy: $new_id"
    exit 0
  fi
  attempt=$((attempt + 1))
  sleep 2
done

echo "[deploy] health check failed; rolling back to $old_id" >&2
if [ -n "$old_id" ]; then
  docker tag "$old_id" "$image_ref"
  docker compose up -d --no-deps --force-recreate wechat-ai
fi
exit 1

