#!/usr/bin/env bash
set -e

PORT=${PORT:-8080}
sed "s/\${{PORT}}/$PORT/g" nginx.conf.template > nginx.conf

exec moon exec -- openresty -p "$PWD" -c nginx.conf
