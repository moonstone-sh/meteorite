#!/bin/bash
export PORT="${PORT:-8080}"
exec moon run app.lua
