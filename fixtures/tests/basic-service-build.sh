#!/usr/bin/env bash
set -Eeuo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
meteorite_test_setup
meteorite_test_trap "basic-service-build"

meteorite_export_basic_service

test -f fixtures/apps/basic-service/.meteorite/graph/current/graph.zig
test -f fixtures/apps/basic-service/.meteorite/graph/current/patterns.graph.json
test -f fixtures/apps/basic-service/.meteorite/graph/current/capabilities.zon
test -x fixtures/apps/basic-service/dist/server

grep -q 'base_url = "http://localhost:8888"' fixtures/apps/basic-service/.meteorite/graph/current/capabilities.zon
grep -q 'data_cruncher = "zig/helpers/data_cruncher.zig"' fixtures/apps/basic-service/.meteorite/graph/current/capabilities.zon
grep -q '"strategy": "class_dfa"' fixtures/apps/basic-service/.meteorite/graph/current/patterns.graph.json
grep -q '"alphabet_classes": 10' fixtures/apps/basic-service/.meteorite/graph/current/patterns.graph.json
grep -q '"backtracking": false' fixtures/apps/basic-service/.meteorite/graph/current/patterns.graph.json
grep -q 'PUT' fixtures/apps/basic-service/.meteorite/graph/current/capabilities.zon
grep -q 'PATCH' fixtures/apps/basic-service/.meteorite/graph/current/capabilities.zon
grep -q 'DELETE' fixtures/apps/basic-service/.meteorite/graph/current/capabilities.zon
grep -q 'field put fun(self: MeteoriteApp' fixtures/apps/basic-service/.meteorite/aids/lua/meteorite.meta.lua
grep -q 'field patch fun(self: MeteoriteApp' fixtures/apps/basic-service/.meteorite/aids/lua/meteorite.meta.lua
grep -q 'field delete fun(self: MeteoriteApp' fixtures/apps/basic-service/.meteorite/aids/lua/meteorite.meta.lua
test -f fixtures/apps/basic-service/.meteorite/aids/lua/meteorite.lua
grep -q 'return meteorite' fixtures/apps/basic-service/.meteorite/aids/lua/meteorite.lua
grep -q 'memory profile: default' fixtures/apps/basic-service/.meteorite/graph/current/build-report.txt
grep -q 'peak route memory:' fixtures/apps/basic-service/.meteorite/graph/current/build-report.txt
grep -q 'max URI: 8kb' fixtures/apps/basic-service/.meteorite/graph/current/build-report.txt
grep -q 'DFA static data:' fixtures/apps/basic-service/.meteorite/graph/current/build-report.txt
grep -q 'max_uri_bytes = 8192' fixtures/apps/basic-service/.meteorite/graph/current/graph.zig
grep -q 'RouteMemory' fixtures/apps/basic-service/.meteorite/graph/current/graph.zig
grep -q 'memory = .{' fixtures/apps/basic-service/.meteorite/graph/current/runtime.zon

echo "PASS: basic-service build artifact"
