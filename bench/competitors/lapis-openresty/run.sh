#!/bin/bash
set -e

# Run moon sync to install dependencies
moon sync

# Create logs directory for nginx
mkdir -p logs

export PORT="${PORT:-8080}"
export LAPIS_ENVIRONMENT="production"

# Execute lapis server (this will block because nginx.conf has daemon off)
exec moon run lapis server production
