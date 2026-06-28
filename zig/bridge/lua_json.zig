const std = @import("std");
const c_imports = @import("c_imports.zig");
const c = c_imports.c;

/// Encode a Lua value at the given stack index as JSON into an ArrayList.
pub fn encodeLuaValue(L: ?*c.lua_State, idx: c_int, list: *std.ArrayListUnmanaged(u8), allocator: std.mem.Allocator) !void {
    const top = c.lua_gettop(L);
    const abs_idx = if (idx <= 0) top + idx + 1 else idx;

    const t = c.lua_type(L, abs_idx);
    switch (t) {
        c.LUA_TNIL => try list.appendSlice(allocator, "null"),
        c.LUA_TBOOLEAN => try list.appendSlice(allocator, if (c.lua_toboolean(L, abs_idx) != 0) "true" else "false"),
        c.LUA_TNUMBER => {
            const buf = if (c.lua_isinteger(L, abs_idx) != 0)
                try std.fmt.allocPrint(allocator, "{d}", .{c.lua_tointegerx(L, abs_idx, @as([*c]c_int, null))})
            else
                try std.fmt.allocPrint(allocator, "{d}", .{c.lua_tonumberx(L, abs_idx, @as([*c]c_int, null))});
            defer allocator.free(buf);
            try list.appendSlice(allocator, buf);
        },
        c.LUA_TSTRING => {
            var len: usize = 0;
            const ptr = c.lua_tolstring(L, abs_idx, &len);
            try list.appendSlice(allocator, "\"");
            try encodeJsonString(ptr[0..len], list, allocator);
            try list.appendSlice(allocator, "\"");
        },
        c.LUA_TTABLE => {
            const len = c.lua_rawlen(L, abs_idx);
            if (len > 0) {
                try list.appendSlice(allocator, "[");
                var i: usize = 1;
                while (i <= len) : (i += 1) {
                    if (i > 1) try list.appendSlice(allocator, ",");
                    c.lua_pushinteger(L, @intCast(i));
                    _ = c.lua_gettable(L, abs_idx);
                    try encodeLuaValue(L, c.lua_gettop(L), list, allocator);
                    c.lua_pop(L, 1);
                }
                try list.appendSlice(allocator, "]");
            } else {
                try list.appendSlice(allocator, "{");
                var first = true;
                c.lua_pushnil(L);
                while (c.lua_next(L, abs_idx) != 0) {
                    if (!first) try list.appendSlice(allocator, ",");
                    first = false;
                    var key_len: usize = 0;
                    const key_ptr = c.lua_tolstring(L, -2, &key_len);
                    try list.appendSlice(allocator, "\"");
                    try encodeJsonString(key_ptr[0..key_len], list, allocator);
                    try list.appendSlice(allocator, "\":");
                    try encodeLuaValue(L, c.lua_gettop(L), list, allocator);
                    c.lua_pop(L, 1);
                }
                try list.appendSlice(allocator, "}");
            }
        },
        else => try list.appendSlice(allocator, "null"),
    }
}

pub fn encodeJsonString(s: []const u8, list: *std.ArrayListUnmanaged(u8), allocator: std.mem.Allocator) !void {
    for (s) |ch| {
        switch (ch) {
            '\\' => try list.appendSlice(allocator, "\\\\"),
            '"' => try list.appendSlice(allocator, "\\\""),
            0...31 => {
                const buf = try std.fmt.allocPrint(allocator, "\\u{x:0>4}", .{ch});
                defer allocator.free(buf);
                try list.appendSlice(allocator, buf);
            },
            else => try list.append(allocator, ch),
        }
    }
}
