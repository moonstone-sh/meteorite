#!/bin/bash
rm -f dist/server
ZIG_GLOBAL_CACHE_DIR=/tmp/zig-cache-bench zig build install-server -Dgraph-input=fixtures/apps/bench-service/src/main.lua -Dgraph-output=.meteorite/graph/bench -Dmode=release-hybrid -Dfast-http-strategy=pool
./dist/server & pid=$!
sleep 2
curl -s http://127.0.0.1:8080/__bench/stats/reset -X POST
wrk -t 1 -c 1 -d 2s http://127.0.0.1:8080/__app/json/encode-small 
curl -s http://127.0.0.1:8080/__bench/stats | python3 -c 'import sys, json; print(json.load(sys.stdin)["routes"]["app-json-encode-small"])'
kill -9 $pid
