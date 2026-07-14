const c_imports = @import("c_imports.zig");
const c = c_imports.c;

const LuaAbi = enum {
    lua_5_4,
    lua_5_1,
    unknown,
};

const lua_abi: LuaAbi = if (@hasDecl(c, "lua_pcallk")) .lua_5_4 else if (@hasDecl(c, "lua_pcall")) .lua_5_1 else .unknown;

pub const LUA_OK = if (lua_abi == .lua_5_4) c.LUA_OK else 0;

pub inline fn pcall(L: *c.lua_State, nargs: c_int, nresults: c_int, errfunc: c_int) c_int {
    switch (comptime lua_abi) {
        .lua_5_4 => return c.lua_pcallk(L, nargs, nresults, errfunc, 0, null),
        .lua_5_1 => return c.lua_pcall(L, nargs, nresults, errfunc),
        else => @compileError("Undefined ABI layout: " ++ @tagName(lua_abi)),
    }
}

pub inline fn loadfile(L: *c.lua_State, filename: [*c]const u8) c_int {
    switch (comptime lua_abi) {
        .lua_5_4 => return c.luaL_loadfilex(L, filename, null),
        .lua_5_1 => return c.luaL_loadfile(L, filename),
        else => @compileError("Undefined ABI layout: " ++ @tagName(lua_abi)),
    }
}

pub inline fn getStatusInt(L: *c.lua_State, idx: c_int, default: u16) u16 {
    switch (comptime lua_abi) {
        .lua_5_4 => {
            if (c.lua_isinteger(L, idx) != 0) return @intCast(c.lua_tointegerx(L, idx, null));
        },
        .lua_5_1 => {
            if (c.lua_isnumber(L, idx) != 0) return @intCast(c.lua_tointeger(L, idx));
        },
        else => @compileError("Undefined ABI layout: " ++ @tagName(lua_abi)),
    }
    return default;
}
