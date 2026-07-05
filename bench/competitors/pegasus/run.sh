#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -e

# Run moon sync to fetch dependencies
moon sync

# Ensure PORT is set
export PORT="${PORT:-8080}"

# Run the app. We use `exec` so that SIGTERM is properly received by the lua process.
# `moon run` might not forward signals perfectly, but using `moon exec` or standard `LUA_PATH` is better.
# We'll use `moon exec` to run lua so dependencies are loaded.
exec moon exec -- lua app.lua
