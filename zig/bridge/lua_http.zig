const std = @import("std");
const vtable = @import("lua_vtable.zig");
const json = @import("lua_json.zig");

pub const HttpResponse = struct {
    allocator: std.mem.Allocator,
    status: u16,
    headers: []const u8,
    body: []const u8,

    pub fn deinit(self: HttpResponse) void {
        self.allocator.free(self.headers);
        self.allocator.free(self.body);
    }
};

pub const RequestHeader = struct {
    name: []const u8,
    value: []const u8,
};

pub const HttpClient = struct {
    base_url: []const u8,
    timeout_ms: u32,
    max_response_bytes: usize,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, base_url: []const u8, timeout_ms: u32, max_response_bytes: usize) HttpClient {
        return .{ .allocator = allocator, .base_url = base_url, .timeout_ms = timeout_ms, .max_response_bytes = max_response_bytes };
    }

    pub fn request(self: HttpClient, method: []const u8, path: []const u8, body: ?[]const u8, headers_in: []const RequestHeader) !HttpResponse {
        const base = std.mem.trimEnd(u8, self.base_url, "/");
        const separator = if (path.len == 0 or path[0] != '/') "/" else "";
        const url = try std.fmt.allocPrint(self.allocator, "{s}{s}{s}", .{ base, separator, path });
        defer self.allocator.free(url);

        const ctx = vtable.current_ctx.?;
        const vt = vtable.current_vtable.?;

        var args = std.ArrayListUnmanaged([]const u8).empty;
        defer args.deinit(self.allocator);
        const timeout_arg = try std.fmt.allocPrint(self.allocator, "{d}.{d:0>3}", .{ self.timeout_ms / 1000, self.timeout_ms % 1000 });
        defer self.allocator.free(timeout_arg);
        try args.appendSlice(self.allocator, &.{ "curl", "-sS", "-X", method, "--max-time", timeout_arg });

        var tmp_headers: ?[]const u8 = null;
        var tmp_body: ?[]const u8 = null;
        var tmp_req_body: ?[]const u8 = null;
        var body_arg: ?[]const u8 = null;
        var header_args: std.ArrayListUnmanaged([]const u8) = .empty;
        defer {
            const io = vt.io(ctx);
            if (tmp_headers) |p| {
                std.Io.Dir.cwd().deleteFile(io, p) catch {};
                self.allocator.free(p);
            }
            if (tmp_body) |p| {
                std.Io.Dir.cwd().deleteFile(io, p) catch {};
                self.allocator.free(p);
            }
            if (tmp_req_body) |p| {
                std.Io.Dir.cwd().deleteFile(io, p) catch {};
                self.allocator.free(p);
            }
            if (body_arg) |arg| self.allocator.free(arg);
            for (header_args.items) |arg| self.allocator.free(arg);
            header_args.deinit(self.allocator);
        }

        tmp_headers = try self.tempFile(vt.io(ctx), "mt-hdr-");
        tmp_body = try self.tempFile(vt.io(ctx), "mt-body-");
        try args.appendSlice(self.allocator, &.{ "-D", tmp_headers.?, "-o", tmp_body.? });

        if (body) |b| {
            tmp_req_body = try self.tempFile(vt.io(ctx), "mt-req-");
            const f = try std.Io.Dir.cwd().createFile(vt.io(ctx), tmp_req_body.?, .{});
            defer f.close(vt.io(ctx));
            try f.writeStreamingAll(vt.io(ctx), b);
            body_arg = try std.fmt.allocPrint(self.allocator, "@{s}", .{tmp_req_body.?});
            try args.appendSlice(self.allocator, &.{ "--data-binary", body_arg.? });
        }

        for (headers_in) |header| {
            const header_arg = try std.fmt.allocPrint(self.allocator, "{s}: {s}", .{ header.name, header.value });
            try header_args.append(self.allocator, header_arg);
            try args.appendSlice(self.allocator, &.{ "-H", header_arg });
        }
        try args.append(self.allocator, url);

        const output = try vt.run(ctx, self.allocator, args.items);
        defer self.allocator.free(output);

        const headers_raw = try self.readFile(vt.io(ctx), tmp_headers.?);
        defer self.allocator.free(headers_raw);
        const status_line = extractStatus(headers_raw);
        if (status_line == 0) return error.HttpRequestFailed;
        const headers = try self.allocator.dupe(u8, headers_raw);
        errdefer self.allocator.free(headers);

        const body_out = try self.readFile(vt.io(ctx), tmp_body.?);
        errdefer self.allocator.free(body_out);
        if (body_out.len > self.max_response_bytes) {
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
};

fn extractStatus(raw: []const u8) u16 {
    var lines = std.mem.splitAny(u8, raw, "\r\n");
    var status: u16 = 0;
    while (lines.next()) |line| {
        if (!std.mem.startsWith(u8, line, "HTTP/") or line.len < 12) continue;
        const first_space = std.mem.indexOfScalar(u8, line, ' ') orelse continue;
        if (first_space + 4 > line.len) continue;
        status = std.fmt.parseInt(u16, line[first_space + 1 .. first_space + 4], 10) catch status;
    }
    return status;
}
