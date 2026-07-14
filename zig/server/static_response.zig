const std = @import("std");

pub fn StaticResponse(comptime graph: anytype, comptime backend: anytype, comptime server_static: anytype, comptime Captures: type, comptime Io: type) type {
    return struct {
        fn accepts(request: *backend.Request, expected: []const u8) bool {
            const header_value = backend.header(request, "accept") orelse return true;
            return mediaListAccepts(header_value, expected);
        }

        fn mediaListAccepts(header_value: []const u8, expected: []const u8) bool {
            const slash = std.mem.indexOfScalar(u8, expected, '/') orelse return server_static.tokenListContains(header_value, expected);
            const expected_type = expected[0..slash];
            const expected_subtype_end = std.mem.indexOfScalarPos(u8, expected, slash + 1, ';') orelse expected.len;
            const expected_subtype = std.mem.trim(u8, expected[slash + 1 .. expected_subtype_end], " \t");
            var it = std.mem.splitScalar(u8, header_value, ',');
            while (it.next()) |raw_item| {
                const media_range = std.mem.trim(u8, raw_item, " \t");
                if (media_range.len == 0 or server_static.qualityIsZero(media_range)) continue;
                const token_end = std.mem.indexOfScalar(u8, media_range, ';') orelse media_range.len;
                const token = std.mem.trim(u8, media_range[0..token_end], " \t");
                if (std.mem.eql(u8, token, "*/*")) return true;
                const token_slash = std.mem.indexOfScalar(u8, token, '/') orelse continue;
                const token_type = token[0..token_slash];
                const token_subtype = token[token_slash + 1 ..];
                if (!std.ascii.eqlIgnoreCase(token_type, expected_type)) continue;
                if (std.mem.eql(u8, token_subtype, "*")) return true;
                if (std.ascii.eqlIgnoreCase(token_subtype, expected_subtype)) return true;
            }
            return false;
        }

        pub fn serveFileHandler(comptime handler: graph.FileHandler, allocator: std.mem.Allocator, io: Io, request: *backend.Request) !void {
            if (handler.only_accept) |expected| {
                if (!accepts(request, expected)) return backend.respondText(request, 404, "not found");
            }
            try respondStaticFile(allocator, io, request, handler.artifact_path, handler.content_type, handler.content_length, handler.cache_control, handler.etag, null);
        }

        pub fn serveDirHandler(comptime handler: graph.DirHandler, allocator: std.mem.Allocator, io: Io, request: *backend.Request, captures: Captures) !void {
            const raw_path = captures.get(handler.param_name) orelse return backend.respondText(request, 404, "not found");
            const normalized = server_static.normalizeStaticPath(allocator, raw_path) catch return backend.respondText(request, 404, "not found");
            defer allocator.free(normalized);
            inline for (handler.manifest) |asset| {
                if (std.mem.eql(u8, asset.request_path, normalized)) {
                    if (selectCompressedAsset(request, asset)) |selected| {
                        return respondStaticFile(allocator, io, request, selected.path, asset.content_type, selected.length, asset.cache_control, selected.etag, selected.encoding);
                    }
                    return respondStaticFile(allocator, io, request, asset.artifact_path, asset.content_type, asset.content_length, asset.cache_control, asset.etag, null);
                }
            }
            return backend.respondText(request, 404, "not found");
        }

        const SelectedAsset = struct { path: []const u8, length: u64, etag: []const u8, encoding: []const u8 };

        fn selectCompressedAsset(request: *backend.Request, comptime asset: graph.StaticAsset) ?SelectedAsset {
            const accept_encoding = backend.header(request, "accept-encoding") orelse return null;
            if (asset.compressed_br_path) |path| {
                if (server_static.tokenListContains(accept_encoding, "br")) return .{ .path = path, .length = asset.compressed_br_length, .etag = asset.compressed_br_etag orelse asset.etag, .encoding = "br" };
            }
            if (asset.compressed_gzip_path) |path| {
                if (server_static.tokenListContains(accept_encoding, "gzip")) return .{ .path = path, .length = asset.compressed_gzip_length, .etag = asset.compressed_gzip_etag orelse asset.etag, .encoding = "gzip" };
            }
            return null;
        }

        fn respondStaticFile(allocator: std.mem.Allocator, io: Io, request: *backend.Request, artifact_path: []const u8, content_type: []const u8, content_length: u64, cache_control: []const u8, etag: []const u8, content_encoding: ?[]const u8) !void {
            const head_only = backend.method(request) == .HEAD;
            if (backend.header(request, "if-none-match")) |value| {
                if (server_static.ifNoneMatch(value, etag)) {
                    return backend.respondStatic(request, 304, content_type, 0, cache_control, etag, content_encoding, "", head_only);
                }
            }
            if (head_only) return backend.respondStatic(request, 200, content_type, content_length, cache_control, etag, content_encoding, "", true);
            const body = try server_static.readArtifactFile(allocator, io, artifact_path, content_length);
            defer allocator.free(body);
            return backend.respondStatic(request, 200, content_type, content_length, cache_control, etag, content_encoding, body, head_only);
        }
    };
}
