const std = @import("std");
const process = std.process;

/// Path captures reach handlers percent-decoded, like query values do.
/// Captures are stored raw: static directory routes read them directly and
/// validate the encoded form themselves (decoding here too would double-
/// decode). Malformed escapes are kept literally; `+` is not a space in paths.
pub fn decodeCapture(allocator: std.mem.Allocator, raw: []const u8) []const u8 {
    if (std.mem.indexOfScalar(u8, raw, '%') == null) return raw;
    var out = allocator.alloc(u8, raw.len) catch return raw;
    var len: usize = 0;
    var i: usize = 0;
    while (i < raw.len) {
        if (raw[i] == '%' and i + 2 < raw.len) {
            const hi = std.fmt.charToDigit(raw[i + 1], 16) catch null;
            const lo = std.fmt.charToDigit(raw[i + 2], 16) catch null;
            if (hi != null and lo != null) {
                out[len] = @intCast((hi.? << 4) | lo.?);
                len += 1;
                i += 3;
                continue;
            }
        }
        out[len] = raw[i];
        len += 1;
        i += 1;
    }
    return out[0..len];
}

pub fn RequestContext(comptime backend: anytype, comptime protocol: anytype, comptime build_info: anytype, comptime request_id: anytype, comptime backendProtocolMethod: anytype, comptime queryValue: anytype, comptime queryAllValues: anytype) type {
    return struct {
        pub fn captureEntries(ctx: anytype) ![]const protocol.MetadataEntry {
            var entries = try ctx.allocator.alloc(protocol.MetadataEntry, ctx.route.params.len);
            var count: usize = 0;
            for (ctx.route.params) |param_spec| {
                if (ctx.captures.get(param_spec.name)) |value| {
                    entries[count] = .{ .name = param_spec.name, .value = decodeCapture(ctx.allocator, value) };
                    count += 1;
                }
            }
            return entries[0..count];
        }

        pub fn queryEntries(ctx: anytype) ![]const protocol.MetadataEntry {
            var entries = try ctx.allocator.alloc(protocol.MetadataEntry, ctx.route.query.len);
            var count: usize = 0;
            for (ctx.route.query) |query_spec| {
                if (queryValue(ctx.allocator, ctx.request, query_spec.name)) |value| {
                    entries[count] = .{ .name = query_spec.name, .value = value };
                    count += 1;
                }
            }
            return entries[0..count];
        }

        pub fn requestMetadataEntries(ctx: anytype) ![]const protocol.MetadataEntry {
            var entries = try ctx.allocator.alloc(protocol.MetadataEntry, 5);
            var count: usize = 0;
            if (header(ctx, "content-type")) |content_type| {
                entries[count] = .{ .name = "content_type", .value = content_type };
                count += 1;
            }
            entries[count] = .{ .name = "transport", .value = build_info.transport };
            count += 1;
            if (peer(ctx)) |identity| {
                if (identity.uid) |uid| {
                    entries[count] = .{ .name = "peer_uid", .value = try std.fmt.allocPrint(ctx.allocator, "{d}", .{uid}) };
                    count += 1;
                }
                if (identity.gid) |gid| {
                    entries[count] = .{ .name = "peer_gid", .value = try std.fmt.allocPrint(ctx.allocator, "{d}", .{gid}) };
                    count += 1;
                }
                if (identity.pid) |pid| {
                    entries[count] = .{ .name = "peer_pid", .value = try std.fmt.allocPrint(ctx.allocator, "{d}", .{pid}) };
                    count += 1;
                }
            }
            return entries[0..count];
        }

        pub fn meteoriteRequest(ctx: anytype) !protocol.MeteoriteRequest {
            return .{
                .route_key = ctx.route.canonical_id,
                .message = ctx.route.message.name,
                .method = backendProtocolMethod(backend.method(ctx.request)),
                .path = backend.path(ctx.request),
                .params = try captureEntries(ctx),
                .query = try queryEntries(ctx),
                .metadata = try requestMetadataEntries(ctx),
                .body = ctx.cached_body orelse "",
                .content_type = header(ctx, "content-type"),
                .request_id = try requestId(ctx),
                .peer = peer(ctx),
            };
        }

        pub fn path(ctx: anytype) []const u8 {
            return backend.path(ctx.request);
        }

        /// The unmodified request target is deliberately distinct from path:
        /// a router needs the query string to seed browser/SSR state, while
        /// matcher and file-serving code must operate on the path alone.
        pub fn target(ctx: anytype) []const u8 {
            if (comptime @hasDecl(backend, "target")) return backend.target(ctx.request);
            return backend.path(ctx.request);
        }

        pub fn routeId(ctx: anytype) []const u8 {
            return ctx.route.id;
        }

        pub fn message(ctx: anytype) []const u8 {
            return ctx.route.message.name;
        }

        pub fn run(ctx: anytype, allocator: std.mem.Allocator, argv: []const []const u8) ![]const u8 {
            const result = try process.run(allocator, ctx.io, .{ .argv = argv });
            defer allocator.free(result.stderr);
            errdefer allocator.free(result.stdout);
            switch (result.term) {
                .exited => |code| if (code != 0) return error.SubprocessFailed,
                else => return error.SubprocessFailed,
            }
            return result.stdout;
        }

        pub fn param(ctx: anytype, name: []const u8) ?[]const u8 {
            const raw = ctx.captures.get(name) orelse return null;
            return decodeCapture(ctx.allocator, raw);
        }

        pub fn paramAt(ctx: anytype, index: usize) ?[]const u8 {
            if (index >= ctx.route.params.len) return null;
            const raw = ctx.captures.get(ctx.route.params[index].name) orelse return null;
            return decodeCapture(ctx.allocator, raw);
        }

        pub fn query(ctx: anytype, name: []const u8) ?[]const u8 {
            return queryValue(ctx.allocator, ctx.request, name);
        }

        pub fn queryAll(ctx: anytype, name: []const u8) ?[][]const u8 {
            return queryAllValues(ctx.allocator, ctx.request, name);
        }

        pub fn metadata(ctx: anytype, name: []const u8) ?[]const u8 {
            if (comptime @hasField(@TypeOf(ctx.request.*), "metadata_value")) {
                return backend.header(ctx.request, name);
            }
            return null;
        }

        pub fn peer(ctx: anytype) ?protocol.Peer {
            if (comptime @hasDecl(backend, "peer")) return backend.peer(ctx.request);
            return null;
        }

        pub fn header(ctx: anytype, name: []const u8) ?[]const u8 {
            if (!build_info.capability_http_headers) return null;
            return backend.header(ctx.request, name);
        }

        pub fn requestId(ctx: anytype) ![]const u8 {
            if (ctx.request_id_cache) |value| return value;
            const incoming_id = if (build_info.capability_http_headers) header(ctx, "x-request-id") else metadata(ctx, "request_id");
            if (incoming_id) |incoming| {
                if (request_id.isSafe(incoming)) {
                    ctx.request_id_cache = try ctx.allocator.dupe(u8, incoming);
                    return ctx.request_id_cache.?;
                }
            }
            var random_bytes: [16]u8 = undefined;
            ctx.io.random(&random_bytes);
            const hex = std.fmt.bytesToHex(random_bytes, .lower);
            ctx.request_id_cache = try ctx.allocator.dupe(u8, &hex);
            return ctx.request_id_cache.?;
        }

        pub fn stateGet(ctx: anytype, key: []const u8) ?[]const u8 {
            for (ctx.state[0..ctx.state_len]) |entry| {
                if (std.mem.eql(u8, entry.key, key)) return entry.value;
            }
            return null;
        }

        pub fn stateSet(ctx: anytype, key: []const u8, value: []const u8) !void {
            for (ctx.state[0..ctx.state_len]) |*entry| {
                if (std.mem.eql(u8, entry.key, key)) {
                    entry.value = try ctx.allocator.dupe(u8, value);
                    return;
                }
            }
            if (ctx.state_len >= ctx.state.len) return error.StateLimitExceeded;
            ctx.state[ctx.state_len] = .{ .key = try ctx.allocator.dupe(u8, key), .value = try ctx.allocator.dupe(u8, value) };
            ctx.state_len += 1;
        }

        pub fn body(ctx: anytype) ![]const u8 {
            if (ctx.cached_body) |b| return b;
            ctx.cached_body = backend.readBody(ctx.request, ctx.allocator, ctx.route.max_body_bytes) catch |err| switch (err) {
                error.PayloadTooLarge => {
                    std.debug.print("request body exceeded route limit\n\nroute: {s} {s}\nmax_body_bytes: {d}\n", .{ @tagName(ctx.route.method), ctx.route.raw_path, ctx.route.max_body_bytes });
                    try backend.respondText(ctx.request, 413, "payload too large");
                    ctx.responded = true;
                    return err;
                },
                else => return err,
            };
            return ctx.cached_body.?;
        }
    };
}

test "decodeCapture decodes percent escapes and keeps everything else" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try std.testing.expectEqualStrings("Ada Lovelace", decodeCapture(a, "Ada%20Lovelace"));
    try std.testing.expectEqualStrings("<b>", decodeCapture(a, "%3Cb%3E"));
    try std.testing.expectEqualStrings("a+b", decodeCapture(a, "a+b"));
    try std.testing.expectEqualStrings("100%", decodeCapture(a, "100%"));
    try std.testing.expectEqualStrings("%zz", decodeCapture(a, "%zz"));
    try std.testing.expectEqualStrings("plain", decodeCapture(a, "plain"));
}
