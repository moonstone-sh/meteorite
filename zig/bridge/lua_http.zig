const std = @import("std");
const vtable = @import("lua_vtable.zig");
const json = @import("lua_json.zig");

pub const HttpResponse = struct {
    allocator: std.mem.Allocator,
    status: u16,
    headers: []const u8,
    body: []const u8,

    pub fn pushToLua(self: HttpResponse, L: ?*anyopaque) void {
        // This is called with the Lua C state, but we keep it generic here
        // and let the caller handle the Lua-specific pushing.
        _ = self;
        _ = L;
    }
};

pub const HttpClient = struct {
    base_url: []const u8,
    timeout_ms: u32,
    max_response_bytes: usize,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, base_url: []const u8, timeout_ms: u32, max_response_bytes: usize) HttpClient {
        return .{ .allocator = allocator, .base_url = base_url, .timeout_ms = timeout_ms, .max_response_bytes = max_response_bytes };
    }

    pub fn request(self: HttpClient, method: []const u8, path: []const u8, body: ?[]const u8, content_type: ?[]const u8, auth_header: ?[]const u8) !HttpResponse {
        const url = try std.fs.path.join(self.allocator, &.{ self.base_url, path });
        defer self.allocator.free(url);

        const ctx = vtable.current_ctx.?;
        const vt = vtable.current_vtable.?;

        var args = std.ArrayListUnmanaged([]const u8).empty;
        defer {
            for (args.items) |arg| self.allocator.free(arg);
            args.deinit(self.allocator);
        }
        try args.appendSlice(self.allocator, &.{ "curl", "-s", "-i", "-X", method, "--max-time", "30" });

        var tmp_headers: ?[]const u8 = null;
        var tmp_body: ?[]const u8 = null;
        var tmp_req_body: ?[]const u8 = null;
        defer {
            const io = vt.io(ctx);
            if (tmp_headers) |p| { std.Io.Dir.cwd().deleteFile(io, p) catch {}; self.allocator.free(p); }
            if (tmp_body) |p| { std.Io.Dir.cwd().deleteFile(io, p) catch {}; self.allocator.free(p); }
            if (tmp_req_body) |p| { std.Io.Dir.cwd().deleteFile(io, p) catch {}; self.allocator.free(p); }
        }

        tmp_headers = try self.tempFile(vt.io(ctx), "mt-hdr-");
        tmp_body = try self.tempFile(vt.io(ctx), "mt-body-");
        try args.appendSlice(self.allocator, &.{ "-D", tmp_headers.?, "-o", tmp_body.? });

        if (body) |b| {
            tmp_req_body = try self.tempFile(vt.io(ctx), "mt-req-");
            const f = try std.Io.Dir.cwd().createFile(vt.io(ctx), tmp_req_body.?, .{});
            defer f.close(vt.io(ctx));
            try f.writeStreamingAll(vt.io(ctx), b);
            try args.appendSlice(self.allocator, &.{
                "-d",
                try std.fmt.allocPrint(self.allocator, "@{s}", .{tmp_req_body.?}),
            });
        }

        if (content_type) |ct| {
            try args.appendSlice(self.allocator, &.{
                "-H",
                try std.fmt.allocPrint(self.allocator, "content-type: {s}", .{ct}),
            });
        }
        if (auth_header) |ah| {
            try args.appendSlice(self.allocator, &.{
                "-H",
                try std.fmt.allocPrint(self.allocator, "authorization: {s}", .{ah}),
            });
        }
        try args.append(self.allocator, url);

        const output = try vt.run(ctx, self.allocator, args.items);
        defer self.allocator.free(output);

        const headers_raw = try self.readFile(vt.io(ctx), tmp_headers.?);
        defer self.allocator.free(headers_raw);
        const status_line = extractStatus(headers_raw);
        const headers = try self.parseHeaders(headers_raw);
        errdefer self.allocator.free(headers);

        const body_out = try self.readFile(vt.io(ctx), tmp_body.?);
        errdefer self.allocator.free(body_out);
        if (body_out.len > self.max_response_bytes) {
            self.allocator.free(body_out);
            self.allocator.free(headers);
            return error.ResponseTooLarge;
        }

        return .{
            .allocator = self.allocator,
            .status = status_line,
            .headers = headers,
            .body = body_out,
        };
    }

    fn tempFile(self: HttpClient, io: std.Io, prefix: []const u8) ![]const u8 {
        var buf: [64]u8 = undefined;
        var random_bytes: [8]u8 = undefined;
        io.random(&random_bytes);
        const hex = std.fmt.bytesToHex(random_bytes, .lower);
        const name = try std.fmt.bufPrint(&buf, "{s}{s}", .{ prefix, &hex });
        const file = try std.Io.Dir.cwd().createFile(io, name, .{});
        file.close(io);
        return try self.allocator.dupe(u8, name);
    }

    fn readFile(self: HttpClient, io: std.Io, path: []const u8) ![]const u8 {
        return try std.Io.Dir.cwd().readFileAlloc(io, path, self.allocator, std.Io.Limit.limited(self.max_response_bytes + 1));
    }

    fn parseHeaders(self: HttpClient, raw: []const u8) ![]const u8 {
        var lines = std.mem.splitAny(u8, raw, "\r\n");
        var list: std.ArrayListUnmanaged(u8) = .empty;
        defer list.deinit(self.allocator);
        while (lines.next()) |line| {
            if (line.len == 0) continue;
            const idx = std.mem.indexOfScalar(u8, line, ':') orelse continue;
            if (idx == 0) continue;
            const name = line[0..idx];
            const value = if (idx + 1 < line.len) std.mem.trim(u8, line[idx + 1 ..], " ") else "";
            try list.appendSlice(self.allocator, "\"");
            try json.encodeJsonString(name, &list, self.allocator);
            try list.appendSlice(self.allocator, "\":\"");
            try json.encodeJsonString(value, &list, self.allocator);
            try list.appendSlice(self.allocator, "\",");
        }
        return list.toOwnedSlice(self.allocator);
    }
};

fn extractStatus(raw: []const u8) u16 {
    var lines = std.mem.splitAny(u8, raw, "\r\n");
    const first = lines.next() orelse return 0;
    if (first.len < 12) return 0;
    const code = std.fmt.parseInt(u16, first[9..12], 10) catch return 0;
    return code;
}
