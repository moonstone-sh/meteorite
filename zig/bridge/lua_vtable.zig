const std = @import("std");

/// Virtual table for dispatching context method calls from Lua C bindings
/// to the compile-time-generated Context type in meteorite.zig.
/// This indirection allows bridge.zig to call context methods without
/// knowing the concrete Context type at compile time.
pub const VTable = struct {
    text: *const fn (ctx: *anyopaque, status: u16, body: []const u8) anyerror!void,
    json: *const fn (ctx: *anyopaque, status: u16, body: []const u8) anyerror!void,
    bytes: *const fn (ctx: *anyopaque, status: u16, content_type: []const u8, body: []const u8) anyerror!void,
    body: *const fn (ctx: *anyopaque) anyerror![]const u8,
    param: *const fn (ctx: *anyopaque, name: []const u8) ?[]const u8,
    query: *const fn (ctx: *anyopaque, name: []const u8) ?[]const u8,
    header: *const fn (ctx: *anyopaque, name: []const u8) ?[]const u8,
    allocator: *const fn (ctx: *anyopaque) std.mem.Allocator,
    io: *const fn (ctx: *anyopaque) std.Io,
    run: *const fn (ctx: *anyopaque, allocator: std.mem.Allocator, argv: []const []const u8) anyerror![]const u8,
};

pub fn makeVTable(comptime Ctx: type) VTable {
    return .{
        .text = struct {
            fn f(ptr: *anyopaque, status: u16, body: []const u8) !void {
                const typed: *Ctx = @ptrCast(@alignCast(ptr));
                return typed.text(status, body);
            }
        }.f,
        .json = struct {
            fn f(ptr: *anyopaque, status: u16, body: []const u8) !void {
                const typed: *Ctx = @ptrCast(@alignCast(ptr));
                return typed.json(status, body);
            }
        }.f,
        .bytes = struct {
            fn f(ptr: *anyopaque, status: u16, content_type: []const u8, body: []const u8) !void {
                const typed: *Ctx = @ptrCast(@alignCast(ptr));
                return typed.bytes(status, content_type, body);
            }
        }.f,
        .body = struct {
            fn f(ptr: *anyopaque) ![]const u8 {
                const typed: *Ctx = @ptrCast(@alignCast(ptr));
                return typed.body();
            }
        }.f,
        .param = struct {
            fn f(ptr: *anyopaque, name: []const u8) ?[]const u8 {
                const typed: *Ctx = @ptrCast(@alignCast(ptr));
                return typed.param(name);
            }
        }.f,
        .query = struct {
            fn f(ptr: *anyopaque, name: []const u8) ?[]const u8 {
                const typed: *Ctx = @ptrCast(@alignCast(ptr));
                return typed.query(name);
            }
        }.f,
        .header = struct {
            fn f(ptr: *anyopaque, name: []const u8) ?[]const u8 {
                const typed: *Ctx = @ptrCast(@alignCast(ptr));
                return typed.header(name);
            }
        }.f,
        .allocator = struct {
            fn f(ptr: *anyopaque) std.mem.Allocator {
                const typed: *Ctx = @ptrCast(@alignCast(ptr));
                return typed.allocator;
            }
        }.f,
        .io = struct {
            fn f(ptr: *anyopaque) std.Io {
                const typed: *Ctx = @ptrCast(@alignCast(ptr));
                return typed.io;
            }
        }.f,
        .run = struct {
            fn f(ptr: *anyopaque, allocator: std.mem.Allocator, argv: []const []const u8) anyerror![]const u8 {
                const typed: *Ctx = @ptrCast(@alignCast(ptr));
                return typed.run(allocator, argv);
            }
        }.f,
    };
}

pub fn globalVtable(comptime Ctx: type) *const VTable {
    const static = comptime makeVTable(Ctx);
    return &static;
}

/// Thread-local context state used by Lua C function bindings.
/// Set before each pcall and cleared after.
pub threadlocal var current_ctx: ?*anyopaque = null;
pub threadlocal var current_vtable: ?*const VTable = null;
