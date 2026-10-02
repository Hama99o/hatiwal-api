#!/usr/bin/env bash
# Nightly Hatiwal backup (docs/INFRASTRUCTURE.md §6, layer 2). Installed by Claude Code 2026-10-02.
# main DB + queue DB (gzipped SQL) + photos volume (tar.gz) -> ~/backups/hatiwal/<stamp>/, keep the newest 5.
set -euo pipefail
DIR="$HOME/backups/hatiwal/$(date +%Y%m%d_%H%M%S)"; mkdir -p "$DIR"
for db in hatiwal_production hatiwal_production_queue; do
  docker exec hatiwal_api-db pg_dump -U hatiwal -d "$db" --no-owner --no-acl | gzip > "$DIR/$db.sql.gz"
  gzip -t "$DIR/$db.sql.gz"
done
docker run --rm -v hatiwal_api_storage:/s:ro postgres:16 tar czf - -C /s . > "$DIR/storage.tar.gz"
tar tzf "$DIR/storage.tar.gz" >/dev/null
# Keep the newest 5 backups (by count, not age): if backups ever stop, the
# last good ones are never aged out.
ls -1dt "$HOME"/backups/hatiwal/2*/ 2>/dev/null | tail -n +6 | xargs -r rm -rf
echo "$(date -Is) ok $DIR $(du -sh "$DIR" | cut -f1)" >> "$HOME/backups/hatiwal/backup.log"
# Layer 3: off-server copy to the old OVH VPS (write-only key, rrsync). No --delete:
# a broken or compromised primary must not be able to wipe the copies; that side
# keeps its newest 5.
rsync -a -e "ssh -i $HOME/.ssh/offsite_backup -o IdentitiesOnly=yes -o BatchMode=yes" \
  "$DIR" "$HOME/backups/hatiwal/backup.log" kamal@51.254.130.18:/ \
  && echo "$(date -Is) offsite ok $(basename "$DIR")" >> "$HOME/backups/hatiwal/backup.log" \
  || echo "$(date -Is) OFFSITE FAILED $(basename "$DIR")" >> "$HOME/backups/hatiwal/backup.log"
