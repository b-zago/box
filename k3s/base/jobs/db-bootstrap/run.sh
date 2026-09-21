#!/bin/env bash
# Run the database bootstrap Job and follow its output.
# ./bootstrap-db.sh           # from main
# ./bootstrap-db.sh <ref>     # from a branch, tag or commit

set -euo pipefail

REF="${1:-main}"
MANIFEST="https://raw.githubusercontent.com/b-zago/box/$REF/k3s/base/jobs/db-bootstrap/job.yaml"

kubectl delete -f "$MANIFEST" --ignore-not-found
kubectl apply -f "$MANIFEST"

kubectl wait --for=condition=ready pod -l job-name=db-bootstrap \
  -n postgresql-admin --timeout=120s || true
kubectl logs -f job/db-bootstrap -n postgresql-admin
