#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d /tmp/meteorite-build-api-native.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

(
  cd "$ROOT"
  TARGET="$tmp" moon exec lua -e 'package.path = "src/?.lua;src/?/init.lua;" .. package.path; require("cli.init").run({"init", os.getenv("TARGET"), "--no-sync"}, { print_help = function() end, roots = { install_root = "./", module_root = "src/" } })'
)

lua_bin="$(cd "$ROOT" && moon exec sh -c 'command -v lua')"
if [[ -z "$lua_bin" || ! -x "$lua_bin" ]]; then
  echo "build API native test could not resolve Moonstone's Lua runtime" >&2
  exit 1
fi

mkdir -p "$tmp/.moonstone/env/libexec/meteorite/files"
ln -s "$(dirname "$lua_bin")" "$tmp/.moonstone/env/bin"
ln -s "$ROOT" "$tmp/.moonstone/env/libexec/meteorite/files/meteorite"
mkdir -p "$tmp/deps/answer/src"

(
  cd "$tmp/deps/answer"
  zig init --minimal >/dev/null
  cat > build.zig <<'EOF'
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const module = b.addModule("answer", .{
        .root_source_file = b.path("src/answer.zig"),
        .target = target,
        .optimize = optimize,
    });
    const library = b.addLibrary(.{
        .name = "answer",
        .root_module = module,
        .linkage = .static,
    });
    b.installArtifact(library);
}
EOF
  cat > src/answer.zig <<'EOF'
pub fn value() c_int {
    return 40;
}
EOF
)

cd "$tmp"
zig fetch --save=answer deps/answer >/dev/null

cat > build.zig <<'EOF'
const std = @import("std");
const meteorite = @import(".moonstone/env/libexec/meteorite/files/meteorite/zig/build_api.zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const answer = b.dependency("answer", .{ .target = target, .optimize = optimize });
    const service = meteorite.addService(b, .{
        .meteorite_root = ".moonstone/env/libexec/meteorite/files/meteorite",
        .target = target,
        .optimize = optimize,
        .mode = b.option([]const u8, "mode", "Meteorite build mode") orelse "release-static",
        .backend = b.option([]const u8, "backend", "Meteorite backend") orelse "std_http",
        .native = .{
            .modules = &.{.{ .name = "answer", .module = answer.module("answer") }},
            .libraries = &.{answer.artifact("answer")},
            .include_paths = &.{"native/include"},
            .c_sources = &.{"native/answer.c"},
        },
    });
    const meteorite_step = b.step("meteorite", "Build the Meteorite service");
    meteorite_step.dependOn(service.install_step);
}
EOF

cat > src/app.lua <<'EOF'
local m = require("meteorite")
local app = m.app({ name = "meteorite-build-api-native" })

app:get("/native", {
  summary = "Exercise the native build API",
  responses = { [200] = { description = "Native answer" } },
}, m.zig("zig/handlers/native.zig"))

return app
EOF

mkdir -p native/include zig/handlers
cat > native/include/answer.h <<'EOF'
int answer_c(void);
EOF
cat > native/answer.c <<'EOF'
#include "answer.h"

int answer_c(void) {
    return 2;
}
EOF
cat > zig/handlers/native.zig <<'EOF'
const answer = @import("answer");
const c = @cImport(@cInclude("answer.h"));

pub fn handle(ctx: anytype) !void {
    const total = answer.value() + c.answer_c();
    try ctx.text(200, if (total == 42) "native-42" else "wrong");
}
EOF

"$tmp/.moonstone/env/bin/lua" "$ROOT/src/cli/main.lua" graph src/main.lua .meteorite/graph/current release-static std_http >/dev/null
zig build -Dmode=release-static -Dbackend=std_http -- dist/server
test -x dist/server

echo "PASS: Meteorite Zig Build API resolves a Zig dependency and C source"
