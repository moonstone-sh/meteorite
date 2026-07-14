const c_imports = @import("c_imports.zig");
const c = c_imports.c;
const lua_abi = @import("lua_abi.zig");
const lua_vtable = @import("lua_vtable.zig");
const meteorite_protocol = @import("meteorite_protocol");
const Header = meteorite_protocol.Header;
const VTable = lua_vtable.VTable;
const getStatusInt = lua_abi.getStatusInt;

const ResponseHeaders = struct {
    items: [16]Header = undefined,
    len: usize = 0,

    fn append(self: *ResponseHeaders, name: []const u8, value: []const u8) !void {
        if (self.len >= self.items.len) return error.TooManyResponseHeaders;
        self.items[self.len] = .{ .name = name, .value = value };
        self.len += 1;
    }

    fn slice(self: *const ResponseHeaders) []const Header {
        return self.items[0..self.len];
    }
};

fn absoluteIndex(L: *c.lua_State, index: c_int) c_int {
    return if (index < 0) c.lua_gettop(L) + index + 1 else index;
}

fn parseResponseHeaders(L: *c.lua_State, response_index: c_int) !ResponseHeaders {
    const table_index = absoluteIndex(L, response_index);
    var headers: ResponseHeaders = .{};
    _ = c.lua_getfield(L, table_index, "headers");
    defer c.lua_pop(L, 1);
    if (c.lua_isnil(L, -1)) return headers;
    if (!c.lua_istable(L, -1)) return error.InvalidResponseHeaders;

    const headers_index = absoluteIndex(L, -1);
    c.lua_pushnil(L);
    while (c.lua_next(L, headers_index) != 0) {
        defer c.lua_pop(L, 1);
        if (c.lua_type(L, -2) != c.LUA_TSTRING or c.lua_isstring(L, -1) == 0) return error.InvalidResponseHeaders;
        var name_len: usize = 0;
        const name_ptr = c.lua_tolstring(L, -2, &name_len);
        var value_len: usize = 0;
        const value_ptr = c.lua_tolstring(L, -1, &value_len);
        const name = name_ptr[0..name_len];
        const value = value_ptr[0..value_len];
        try meteorite_protocol.validateResponseHeader(name, value);
        try headers.append(name, value);
    }
    return headers;
}

fn respondLuaTable(L: *c.lua_State, table_index: c_int, ctx: *anyopaque, vtable: *const VTable) !void {
    const response_index = absoluteIndex(L, table_index);
    _ = c.lua_getfield(L, response_index, "status");
    const status: u16 = getStatusInt(L, -1, 200);
    c.lua_pop(L, 1);

    const headers = try parseResponseHeaders(L, response_index);

    _ = c.lua_getfield(L, response_index, "content_type");
    _ = c.lua_getfield(L, response_index, "body");
    defer c.lua_pop(L, 2);
    var content_type_len: usize = 0;
    const content_type_ptr = c.lua_tolstring(L, -2, &content_type_len);
    var body_len: usize = 0;
    const body_ptr = c.lua_tolstring(L, -1, &body_len);
    const body = body_ptr[0..body_len];

    if (content_type_ptr != null) {
        const content_type = content_type_ptr[0..content_type_len];
        return vtable.bytes_with_headers(ctx, status, content_type, body, headers.slice());
    }
    return vtable.bytes_with_headers(ctx, status, "text/plain; charset=utf-8", body, headers.slice());
}

pub fn finish(L: *c.lua_State, ctx: *anyopaque, vtable: *const VTable) !bool {
    if (c.lua_istable(L, -1)) {
        try respondLuaTable(L, -1, ctx, vtable);
        c.lua_pop(L, 1);
        return true;
    }
    if (c.lua_isstring(L, -1) != 0) {
        var len: usize = 0;
        const ptr = c.lua_tolstring(L, -1, &len);
        try vtable.text(ctx, 200, ptr[0..len]);
        c.lua_pop(L, 1);
        return true;
    }
    return false;
}
