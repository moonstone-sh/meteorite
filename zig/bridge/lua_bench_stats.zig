const std = @import("std");

const AtomicCounter = std.atomic.Value(u64);

pub const Tier = enum {
    native,
    lua_empty,
    lua_string_return,
    lua_direct_response,
    lua_response_table,
    lua_direct_param,
    lua_lazy_context,
    lua_full_req,
    lua_body,
    lua_json,
    lua_compute,
    lua_proof_slow,
    lua_dynamic,
    lua_app,
};

pub const RouteStat = struct {
    name: []const u8,
    path: []const u8,
    tier: Tier,
};

pub const routes = [_]RouteStat{
    .{ .name = "zig-static", .path = "/__bench/zig-static", .tier = .native },
    .{ .name = "lua-empty", .path = "/__bench/lua-empty", .tier = .lua_empty },
    .{ .name = "lua-return-string", .path = "/__bench/lua-return-string", .tier = .lua_string_return },
    .{ .name = "lua-text-direct", .path = "/__bench/lua-text-direct", .tier = .lua_direct_response },
    .{ .name = "lua-response-table", .path = "/__bench/lua-response-table", .tier = .lua_response_table },
    .{ .name = "lua-direct-param", .path = "/__bench/lua-direct-param/:id", .tier = .lua_direct_param },
    .{ .name = "lua-ctx-param", .path = "/__bench/lua-ctx-param/:id", .tier = .lua_lazy_context },
    .{ .name = "lua-req-table", .path = "/__bench/lua-req-table/:id", .tier = .lua_full_req },
    .{ .name = "lua-body-1k", .path = "/__bench/lua-body-1k", .tier = .lua_body },
    .{ .name = "lua-json-small", .path = "/__bench/lua-json-small", .tier = .lua_json },
    .{ .name = "lua-state-counter", .path = "/__bench/lua-state-counter", .tier = .lua_dynamic },
    .{ .name = "lua-sleep-1s", .path = "/__bench/lua-sleep-1s", .tier = .lua_proof_slow },
    .{ .name = "lua-echo-param", .path = "/__bench/lua-echo-param/:id", .tier = .lua_dynamic },
    .{ .name = "lua-echo-body", .path = "/__bench/lua-echo-body", .tier = .lua_dynamic },
    .{ .name = "lua-loop-0", .path = "/__bench/lua-loop-0", .tier = .lua_compute },
    .{ .name = "lua-loop-10", .path = "/__bench/lua-loop-10", .tier = .lua_compute },
    .{ .name = "lua-loop-100", .path = "/__bench/lua-loop-100", .tier = .lua_compute },
    .{ .name = "lua-loop-1000", .path = "/__bench/lua-loop-1000", .tier = .lua_compute },
    .{ .name = "lua-loop-10000", .path = "/__bench/lua-loop-10000", .tier = .lua_compute },
    .{ .name = "lua-loop-100000", .path = "/__bench/lua-loop-100000", .tier = .lua_compute },
    .{ .name = "plain_text_hybrid", .path = "/__bench/hybrid-inline", .tier = .lua_string_return },
    .{ .name = "typed_param_hybrid", .path = "/__bench/hybrid-inline-params/:id", .tier = .lua_direct_param },
    .{ .name = "echo_small_hybrid", .path = "/__bench/hybrid-inline-echo", .tier = .lua_body },
    .{ .name = "app-json-encode-small", .path = "/__app/json/encode-small", .tier = .lua_app },
    .{ .name = "app-json-decode-1kb", .path = "/__app/json/decode-1kb", .tier = .lua_app },
    .{ .name = "app-json-roundtrip-1kb", .path = "/__app/json/roundtrip-1kb", .tier = .lua_app },
    .{ .name = "app-template-hello", .path = "/__app/template/hello", .tier = .lua_app },
    .{ .name = "app-template-list-100", .path = "/__app/template/list-100", .tier = .lua_app },
    .{ .name = "app-sqlite-select-one", .path = "/__app/sqlite/select-one", .tier = .lua_app },
    .{ .name = "app-sqlite-select-100", .path = "/__app/sqlite/select-100", .tier = .lua_app },
    .{ .name = "app-sqlite-insert-small", .path = "/__app/sqlite/insert-small", .tier = .lua_app },
    .{ .name = "app-pipeline-cors", .path = "/__app/pipeline/cors", .tier = .lua_app },
    .{ .name = "app-pipeline-cors-json-template", .path = "/__app/pipeline/cors-json-template", .tier = .lua_app },
    .{ .name = "app-full-sqlite-json-template", .path = "/__app/full/sqlite-json-template", .tier = .lua_app },
};

var lua_pcalls: [routes.len]AtomicCounter = initCounters();
var native_calls: [routes.len]AtomicCounter = initCounters();

fn initCounters() [routes.len]AtomicCounter {
    var counters: [routes.len]AtomicCounter = undefined;
    for (&counters) |*counter| counter.* = AtomicCounter.init(0);
    return counters;
}

pub fn tierName(tier: Tier) []const u8 {
    return switch (tier) {
        .native => "native",
        .lua_empty => "lua-empty",
        .lua_string_return => "lua-string-return",
        .lua_direct_response => "lua-direct-response",
        .lua_response_table => "lua-response-table",
        .lua_direct_param => "lua-direct-param",
        .lua_lazy_context => "lua-lazy-context",
        .lua_full_req => "lua-full-req",
        .lua_body => "lua-body",
        .lua_json => "lua-json",
        .lua_compute => "lua-compute",
        .lua_proof_slow => "lua-proof-slow",
        .lua_dynamic => "lua-dynamic",
        .lua_app => "lua-app",
    };
}

pub fn routeIndexByName(name: []const u8) ?usize {
    inline for (routes, 0..) |route, index| {
        if (std.mem.eql(u8, route.name, name)) return index;
    }
    return null;
}

pub fn routeIndexByPath(path: []const u8) ?usize {
    inline for (routes, 0..) |route, index| {
        if (std.mem.eql(u8, route.path, path)) return index;
    }
    return null;
}

pub fn incLuaPcallByPath(path: []const u8) void {
    if (routeIndexByPath(path)) |index| _ = lua_pcalls[index].fetchAdd(1, .monotonic);
}

pub fn incNativeByName(name: []const u8) void {
    if (routeIndexByName(name)) |index| _ = native_calls[index].fetchAdd(1, .monotonic);
}

pub fn reset() void {
    for (&lua_pcalls) |*counter| counter.store(0, .monotonic);
    for (&native_calls) |*counter| counter.store(0, .monotonic);
}

pub fn luaCount(index: usize) u64 {
    return lua_pcalls[index].load(.monotonic);
}

pub fn nativeCount(index: usize) u64 {
    return native_calls[index].load(.monotonic);
}

fn appendJsonString(list: *std.ArrayListUnmanaged(u8), allocator: std.mem.Allocator, value: []const u8) !void {
    try list.append(allocator, '"');
    for (value) |ch| switch (ch) {
        '\\' => try list.appendSlice(allocator, "\\\\"),
        '"' => try list.appendSlice(allocator, "\\\""),
        else => try list.append(allocator, ch),
    };
    try list.append(allocator, '"');
}

pub fn writeJson(list: *std.ArrayListUnmanaged(u8), allocator: std.mem.Allocator) !void {
    try list.appendSlice(allocator, "{\"fixture\":\"bench-service\",\"entry\":\"fixtures/apps/bench-service/src/main.lua\",\"routes\":{");
    inline for (routes, 0..) |route, index| {
        if (index != 0) try list.append(allocator, ',');
        try appendJsonString(list, allocator, route.name);
        try list.appendSlice(allocator, ":{\"path\":");
        try appendJsonString(list, allocator, route.path);
        try list.appendSlice(allocator, ",\"tier\":");
        try appendJsonString(list, allocator, tierName(route.tier));
        const counts = try std.fmt.allocPrint(allocator, ",\"native_calls\":{d},\"lua_pcalls\":{d}}}", .{ nativeCount(index), luaCount(index) });
        defer allocator.free(counts);
        try list.appendSlice(allocator, counts);
    }
    try list.appendSlice(allocator, "}}");
}
