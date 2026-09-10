#!/usr/bin/env sh
set -eu
moon exec lua src/cli/watch_supervisor.lua "$@"
exec bash .meteorite/dev/watch-supervisor.sh
