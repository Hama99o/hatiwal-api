#!/usr/bin/env bash
# Local load test of the PRODUCTION image (docs/LOAD_TEST.md).
#
#   loadtest/run.sh build            build hatiwal-api:loadtest from this checkout's Dockerfile
#   loadtest/run.sh up               start db + redis + api (capped like the VPS), no internet
#   loadtest/run.sh seed             db:seed (categories) + loadtest/seed.rb (the volume)
#   loadtest/run.sh k6 <scenario>    variants | mixed | cable | publish   → loadtest/results/
#   loadtest/run.sh stats            one `docker stats` line per container, every 5 s, to results/stats.log
#   loadtest/run.sh down             stop the stack (keeps the data)
#   loadtest/run.sh reset            stop and DELETE the load-test data volumes
#
# It never touches the dev, QA or production databases: the stack has its own
# Postgres container (loadtest-db, its own volume), and seed.rb refuses any
# other host. The master key is read from config/master.key into the
# environment and never printed.
set -euo pipefail
cd "$(dirname "$0")"
ROOT="$(cd .. && pwd)"
DC=(docker compose -f compose.yml)
mkdir -p tokens results
# The API container runs as uid 1000 and writes tokens/; k6 writes results/.
chmod 0777 tokens results

need_key() {
  [ -f "$ROOT/config/master.key" ] || { echo "config/master.key missing (copy it from hatiwal-api/config)"; exit 1; }
  RAILS_MASTER_KEY="$(cat "$ROOT/config/master.key")"
  export RAILS_MASTER_KEY
  ADMIN_PASSWORD="${ADMIN_PASSWORD:-lt-$(head -c 12 /dev/urandom | base64 | tr -dc A-Za-z0-9)}"
  export ADMIN_PASSWORD
}

print_db() {
  echo "load-test DB: host loadtest-db (container $("${DC[@]}" ps -q loadtest-db | head -c 12)), volume hatiwal-loadtest_loadtest_pg"
  "${DC[@]}" exec -T loadtest-db psql -U hatiwal -Atc "select string_agg(datname, ', ') from pg_database where datname like 'hatiwal%'"
}

case "${1:-}" in
  build)
    docker build -t hatiwal-api:loadtest "$ROOT"
    ;;
  up)
    need_key
    "${DC[@]}" up -d loadtest-db loadtest-redis loadtest-api
    echo "waiting for the API (db:prepare runs on first boot)…"
    for _ in $(seq 1 60); do
      "${DC[@]}" exec -T loadtest-api curl -sf http://localhost/up >/dev/null 2>&1 && break
      sleep 3
    done
    "${DC[@]}" exec -T loadtest-api curl -sf http://localhost/up >/dev/null && echo "API up" || { echo "API not up: ${DC[*]} logs loadtest-api"; exit 1; }
    print_db
    ;;
  seed)
    need_key
    print_db
    "${DC[@]}" exec -T loadtest-api bin/rails db:seed
    "${DC[@]}" exec -T loadtest-api bin/rails runner loadtest/seed.rb
    cp "$ROOT/db/seeds/images/home/sofa-1.jpg" tokens/photo.jpg
    ;;
  k6)
    scenario="${2:?scenario: variants | mixed | cable | publish}"
    [ -f "k6/$scenario.js" ] || { echo "no k6/$scenario.js"; exit 1; }
    need_key # compose needs the variables even for the k6 service
    "${DC[@]}" --profile k6 run --rm k6 run "/scripts/$scenario.js" | tee "results/$scenario-$(date +%Y%m%d-%H%M).log"
    ;;
  stats)
    echo "→ results/stats.log (Ctrl-C to stop)"
    while true; do
      docker stats --no-stream --format '{{.Name}} cpu={{.CPUPerc}} mem={{.MemUsage}}' \
        $("${DC[@]}" ps -q) | sed "s/^/$(date +%T) /" | tee -a results/stats.log
      sleep 5
    done
    ;;
  down)
    need_key
    "${DC[@]}" down
    ;;
  reset)
    need_key
    "${DC[@]}" down -v
    rm -f tokens/*.json tokens/photo.jpg
    ;;
  *)
    sed -n '2,16p' "$0"
    exit 1
    ;;
esac
