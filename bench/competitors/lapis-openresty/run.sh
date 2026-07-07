#!/usr/bin/env bash
set -e

# Run moon sync to install dependencies
moon sync

# Create logs directory for nginx (lapis needs it)
mkdir -p logs

export PORT="${PORT:-8080}"
export LAPIS_ENVIRONMENT="production"

# Execute lapis server using moon exec so Lapis/nginx binaries are on PATH
exec moon exec -- lapis server production
