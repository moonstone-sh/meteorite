#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

bash fixtures/tests/basic-service-build.sh
METEORITE_BASIC_SERVICE_BUILT=1 bash fixtures/tests/basic-service-http.sh
bash fixtures/tests/basic-service-contracts.sh

echo "PASS: Meteorite basic-service fixture acceptance"
