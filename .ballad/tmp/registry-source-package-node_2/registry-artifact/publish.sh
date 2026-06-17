#!/usr/bin/env sh
set -eu
: "${MOONSTONE_TOKEN:=${MOONSTONE_PUBLISH_TOKEN:-}}"
: "${MOONSTONE_TOKEN:?Set MOONSTONE_TOKEN or MOONSTONE_PUBLISH_TOKEN}"
curl --fail-with-body -H "Authorization: Bearer $MOONSTONE_TOKEN" -F descriptor=@"$(dirname "$0")/package.toml" -F blob=@"$(dirname "$0")/meteorite-0.1.0-source.tar.zst" "${MOONSTONE_PUBLISH_URL:-https://moonstone.sh/api/registry/v0/publish}"
