#!/bin/env bash
# Restore a database from its S3 backup, using the Job manifest committed to Git.
# The current database is kept as <target>_broken_<timestamp>.
#
#   ./run-pgsql-restore-job.sh scorevault                                    # latest backup
#   ./run-pgsql-restore-job.sh scorevault 2026-10-18T003000Z.dump            # a specific backup
#   ./run-pgsql-restore-job.sh scorevault latest scorevault_rehearsal        # into a new database, prod untouched
#   REF=<branch> ./run-pgsql-restore-job.sh scorevault                       # manifest from another ref

set -euo pipefail

DB="${1:?usage: $0 <database> [backup-file|latest] [target-database]}"
BACKUP="${2:-latest}"
TARGET="${3:-$DB}"
REF="${REF:-main}"
NS=postgresql-admin
MANIFEST="https://raw.githubusercontent.com/b-zago/box/$REF/k3s/base/jobs/db-restore/job.yaml"

echo "Cluster:  $(kubectl config current-context)"
echo "Restore:  $DB backup '$BACKUP' -> database '$TARGET'"
if [ "$TARGET" = "$DB" ]; then
  echo "The app is disconnected and the current '$DB' is kept as ${DB}_broken_<timestamp>."
fi
read -r -p "Type '$TARGET' to continue: " confirm
[ "$confirm" = "$TARGET" ] || { echo "aborted"; exit 1; }

kubectl create configmap pgsql-restore-params -n "$NS" \
  --from-literal=DB="$DB" --from-literal=BACKUP="$BACKUP" --from-literal=TARGET="$TARGET" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl delete -f "$MANIFEST" --ignore-not-found --wait=true
kubectl apply -f "$MANIFEST"

# Retry: the pod may still be pulling its image, or may fail before it is
# ever Ready, in which case we still want its logs.
for _ in $(seq 60); do
  kubectl logs -f job/db-restore -n "$NS" 2>/dev/null && break
  sleep 2
done

kubectl wait --for=condition=complete job/db-restore -n "$NS" --timeout=10s

if [ "$TARGET" = "$DB" ]; then
  echo "Restart the app so it reconnects, e.g.: kubectl rollout restart deploy/$DB -n <namespace>"
fi
