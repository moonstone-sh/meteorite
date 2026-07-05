#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -e

# Run moon sync to fetch dependencies
moon sync

# Ensure PORT is set
export PORT="${PORT:-8080}"

# Run the app. We use `exec` so that SIGTERM is properly received by the lua process.
exec moon exec -- lapis server production
