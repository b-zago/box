#!/bin/env bash
# Run the database bootstrap Job from the manifest committed to Git.
#
#   ./bootstrap-db.sh           # from main
#   ./bootstrap-db.sh <ref>     # from a branch, tag or commit

set -euo pipefail

REF="${1:-main}"
NS=postgresql-admin
MANIFEST="https://raw.githubusercontent.com/b-zago/box/$REF/k3s/base/jobs/db-bootstrap/job.yaml"

kubectl delete -f "$MANIFEST" --ignore-not-found --wait=true
kubectl apply -f "$MANIFEST"

# Retry: the pod may still be pulling its image, or may fail before it is
# ever Ready, in which case we still want its logs.
for _ in $(seq 60); do
  kubectl logs -f job/db-bootstrap -n "$NS" 2>/dev/null && break
  sleep 2
done

kubectl wait --for=condition=complete job/db-bootstrap -n "$NS" --timeout=10s
