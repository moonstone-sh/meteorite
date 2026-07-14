const std = @import("std");
const Io = std.Io;
const builtin = @import("builtin");
const proto = @import("meteorite_protocol");
const ipc = @import("ipc_protocol.zig");

pub const name = "ipc_unixsocket";
pub const connection_strategy = "unix_socket_single_connection_loop";
pub const bounded = false;
pub const threaded_connections = false;
pub const pooled_connections = false;
pub const configured_workers: u16 = 0;
pub const queue_limit: usize = 0;
pub const supports_peer_credentials = builtin.os.tag == .linux or builtin.os.tag == .macos;

pub const Method = proto.Method;
pub const Header = proto.Header;
pub const Counters = proto.Counters;

var counters: proto.AtomicCounters = .{};

pub fn snapshotCounters() Counters {
    return proto.snapshotCounters(&counters);
}

pub fn resetAuditCounters() void {
    proto.resetAuditCounters(&counters);
}

pub fn requestStarted() void {
    proto.requestStarted(&counters);
}

pub fn requestCompleted() void {
    proto.requestCompleted(&counters);
}

pub fn connectionStarted() void {
    proto.connectionStarted(&counters);
}

pub fn connectionEnded() void {
    proto.connectionEnded(&counters);
}

pub fn connectionError() void {
    proto.inc(&counters.connection_errors);
}

pub fn threadSpawned() void {
    proto.inc(&counters.threads_spawned);
}

pub fn droppedConnection() void {
    proto.inc(&counters.dropped_connections);
}

pub fn setQueueDepth(value: u64) void {
    proto.setQueueDepth(&counters, value);
}

pub const ListenConfig = struct {
    path: []const u8 = "/tmp/meteorite.sock",
    mode: []const u8 = "0660",
    unlink_stale: bool = true,
    io: Io,
};

pub const Server = struct {
    io: Io,
    inner: Io.net.Server,
    path: []const u8,
    cleanup_socket: bool,

    pub fn deinit(self: *Server) void {
        self.inner.deinit(self.io);
        if (self.cleanup_socket) {
            Io.Dir.deleteFileAbsolute(self.io, self.path) catch {};
        }
    }
};

pub const Request = struct {
    stream: Io.net.Stream,
    recv_buffer: [16384]u8 = undefined,
    send_buffer: [8192]u8 = undefined,
    reader: Io.net.Stream.Reader = undefined,
    writer: Io.net.Stream.Writer = undefined,
    closed: bool = false,
    close_after_response: bool = true,
    frame_buffer: []u8 = &.{},
    metadata_value: []const u8 = "",
    query_value: []const u8 = "",
    body_cache: ?[]const u8 = null,
    request_id: u64 = 0,
    target_value: []const u8 = "",
    request_count: u64 = 0,
    peer: ?proto.Peer = null,

    pub fn close(self: *Request, io: Io) void {
        if (self.frame_buffer.len > 0) {
            std.heap.smp_allocator.free(self.frame_buffer);
            self.frame_buffer = &.{};
        }
        if (!self.closed) {
            self.closed = true;
            proto.inc(&counters.connection_close_count);
            self.stream.close(io);
        }
    }
};

fn validateSocketPath(socket_path: []const u8) !void {
    if (socket_path.len == 0) return error.EmptySocketPath;
    if (socket_path[0] != '/') return error.RelativeSocketPath;
    if (std.mem.indexOfScalar(u8, socket_path, 0) != null) return error.InvalidSocketPath;
    if (socket_path.len > Io.net.UnixAddress.max_len) return error.NameTooLong;
}

fn parseMode(mode: []const u8) !std.c.mode_t {
    var text = mode;
    if (text.len == 4 and text[0] == '0') text = text[1..];
    if (text.len != 3) return error.InvalidSocketMode;
    return @intCast(try std.fmt.parseInt(u16, text, 8));
}

fn unlinkStaleSocket(io: Io, socket_path: []const u8, enabled: bool) !void {
    if (!enabled) return;
    const stat = Io.Dir.statFile(Io.Dir.cwd(), io, socket_path, .{ .follow_symlinks = false }) catch |err| switch (err) {
        error.FileNotFound => return,
        else => return err,
    };
    if (stat.kind != .unix_domain_socket) return error.StalePathIsNotSocket;
    try Io.Dir.deleteFileAbsolute(io, socket_path);
}

fn chmodSocket(socket_path: []const u8, mode: []const u8) !void {
    if (!builtin.link_libc) return;
    const parsed = try parseMode(mode);
    var path_z: [Io.net.UnixAddress.max_len + 1:0]u8 = undefined;
    @memcpy(path_z[0..socket_path.len], socket_path);
    path_z[socket_path.len] = 0;
    if (std.c.chmod(&path_z, parsed) != 0) return error.ChmodFailed;
}

pub fn listen(config: ListenConfig) !Server {
    try validateSocketPath(config.path);
    try unlinkStaleSocket(config.io, config.path, config.unlink_stale);
    const address = try Io.net.UnixAddress.init(config.path);
    var server = Server{
        .io = config.io,
        .inner = try address.listen(config.io, .{}),
        .path = config.path,
        .cleanup_socket = true,
    };
    errdefer server.deinit();
    try chmodSocket(config.path, config.mode);
    return server;
}

pub fn accept(server: *Server, req: *Request) !void {
    req.* = Request{ .stream = try server.inner.accept(server.io) };
    proto.inc(&counters.total_connections);
    req.peer = readPeerCredentials(req.stream) catch null;
    req.reader = req.stream.reader(server.io, &req.recv_buffer);
    req.writer = req.stream.writer(server.io, &req.send_buffer);
}

pub fn peer(req: *Request) ?proto.Peer {
    return req.peer;
}

pub fn peerAuthorized(req: *Request, allow_uid: []const u8, allow_gid: []const u8) bool {
    if (allow_uid.len == 0 and allow_gid.len == 0) return req.peer != null;
    const identity = req.peer orelse return false;
    if (allow_uid.len > 0) {
        const allowed = std.fmt.parseInt(u32, allow_uid, 10) catch return false;
        if (identity.uid != allowed) return false;
    }
    if (allow_gid.len > 0) {
        const allowed = std.fmt.parseInt(u32, allow_gid, 10) catch return false;
        if (identity.gid != allowed) return false;
    }
    return true;
}

pub fn unauthorizedPeer(req: *Request) void {
    proto.inc(&counters.unauthorized_peers);
    respondResult(req, .unauthorized_peer, "text/plain; charset=utf-8", "", "unauthorized peer") catch {
        proto.inc(&counters.connection_errors);
    };
}

pub fn rebind(req: *Request, io: Io) void {
    req.reader = req.stream.reader(io, &req.recv_buffer);
    req.writer = req.stream.writer(io, &req.send_buffer);
}

pub fn receiveHead(req: *Request) !void {
    if (req.frame_buffer.len > 0) {
        std.heap.smp_allocator.free(req.frame_buffer);
        req.frame_buffer = &.{};
    }
    req.metadata_value = "";
    req.query_value = "";
    req.body_cache = null;
    req.request_id = 0;
    req.target_value = "";

    var len_prefix: [4]u8 = undefined;
    req.reader.interface.readSliceAll(&len_prefix) catch |err| switch (err) {
        error.ReadFailed, error.EndOfStream => {
            if (req.request_count == 0) proto.inc(&counters.early_closes);
            return error.HttpConnectionClosing;
        },
    };
    proto.add(&counters.bytes_read, 4);
    const declared_len = std.mem.readInt(u32, &len_prefix, .little);
    if (declared_len > ipc.max_frame_size - 4) {
        proto.inc(&counters.oversized_frames);
        return error.PayloadTooLarge;
    }
    const total_len: usize = @as(usize, declared_len) + 4;
    req.frame_buffer = try std.heap.smp_allocator.alloc(u8, total_len);
    @memcpy(req.frame_buffer[0..4], &len_prefix);
    req.reader.interface.readSliceAll(req.frame_buffer[4..]) catch {
        proto.inc(&counters.malformed_frames);
        proto.inc(&counters.early_closes);
        return error.BadRequest;
    };
    proto.add(&counters.bytes_read, declared_len);
    if (ipc.peekRequestId(req.frame_buffer)) |request_id| req.request_id = request_id;
    const parsed = ipc.parseRequestFrame(req.frame_buffer) catch |err| switch (err) {
        error.FrameTooLarge, error.RouteTooLarge, error.MetadataTooLarge, error.BodyTooLarge => {
            proto.inc(&counters.oversized_frames);
            return error.PayloadTooLarge;
        },
        error.UnsupportedVersion, error.UnsupportedFlags => {
            proto.inc(&counters.protocol_errors);
            return error.BadRequest;
        },
        else => {
            proto.inc(&counters.malformed_frames);
            return error.BadRequest;
        },
    };
    req.request_id = parsed.request_id;
    req.target_value = parsed.route;
    req.metadata_value = parsed.metadata;
    req.query_value = header(req, "query") orelse "";
    req.body_cache = parsed.body;
    if (req.request_count > 0) proto.inc(&counters.keepalive_reuse_count);
    req.request_count += 1;
}

pub fn method(req: *Request) Method {
    _ = req;
    return .OTHER;
}

pub fn path(req: *Request) []const u8 {
    return req.target_value;
}

pub fn query(req: *Request) []const u8 {
    return req.query_value;
}

pub fn header(req: *Request, header_name: []const u8) ?[]const u8 {
    var lines = std.mem.splitScalar(u8, req.metadata_value, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        const separator = std.mem.indexOfScalar(u8, line, '=') orelse continue;
        const metadata_name = line[0..separator];
        if (std.ascii.eqlIgnoreCase(metadata_name, header_name)) return line[separator + 1 ..];
        if (std.ascii.eqlIgnoreCase(header_name, "content-type") and std.ascii.eqlIgnoreCase(metadata_name, "content_type")) return line[separator + 1 ..];
    }
    return null;
}

pub const ReadBodyError = std.mem.Allocator.Error || error{ PayloadTooLarge, ReadFailed };

pub fn readBody(req: *Request, allocator: std.mem.Allocator, max_bytes: usize) ReadBodyError![]const u8 {
    const body = req.body_cache orelse "";
    if (body.len > max_bytes) return error.PayloadTooLarge;
    return allocator.dupe(u8, body);
}

pub fn respondParseError(req: *Request, status: u16, body: []const u8) void {
    respondText(req, status, body) catch {
        proto.inc(&counters.connection_errors);
    };
}

pub fn respondText(req: *Request, status: u16, body: []const u8) !void {
    try respondBytes(req, status, "text/plain; charset=utf-8", body);
}

pub fn respondTextWithHeaders(req: *Request, status: u16, body: []const u8, extra_headers: []const Header) !void {
    try respondBytesWithHeaders(req, status, "text/plain; charset=utf-8", body, extra_headers);
}

pub fn respondBytes(req: *Request, status: u16, content_type: []const u8, body: []const u8) !void {
    try respondBytesWithHeaders(req, status, content_type, body, &.{});
}

pub fn respondBytesWithHeaders(req: *Request, status: u16, content_type: []const u8, body: []const u8, extra_headers: []const Header) !void {
    var metadata_buffer: [4096]u8 = undefined;
    var metadata_writer = std.Io.Writer.fixed(&metadata_buffer);
    var has_validation_metadata = false;
    for (extra_headers) |extra_header| {
        const metadata_name = ipcMetadataName(extra_header.name);
        if (std.mem.startsWith(u8, metadata_name, "meteorite.validation.")) has_validation_metadata = true;
        try metadata_writer.print("{s}={s}\n", .{ metadata_name, extra_header.value });
    }
    const metadata = metadata_writer.buffered();

    const result = ipcResultCodeForStatus(status, has_validation_metadata);

    try respondResult(req, result, content_type, metadata, body);
}

fn respondResult(req: *Request, result: proto.ResultCode, content_type: []const u8, metadata: []const u8, body: []const u8) !void {
    const total_len = try ipc.responseFrameLen(content_type.len, metadata.len, body.len);
    const frame = try std.heap.smp_allocator.alloc(u8, total_len);
    defer std.heap.smp_allocator.free(frame);
    const encoded = try ipc.writeResponseFrame(frame, .{
        .request_id = req.request_id,
        .result = result,
        .content_type = content_type,
        .metadata = metadata,
        .body = body,
    });
    try req.writer.interface.writeAll(encoded);
    try req.writer.interface.flush();
    proto.inc(&counters.requests_served);
    proto.add(&counters.bytes_written, encoded.len);
}

fn readPeerCredentials(stream: Io.net.Stream) !?proto.Peer {
    if (!supports_peer_credentials) return null;
    if (!builtin.link_libc) return null;
    const fd = stream.socket.handle;
    return switch (builtin.os.tag) {
        .linux => try readLinuxPeerCredentials(fd),
        .macos => try readDarwinPeerCredentials(fd),
        else => null,
    };
}

fn readLinuxPeerCredentials(fd: std.posix.fd_t) !proto.Peer {
    const UCred = extern struct {
        pid: std.c.pid_t,
        uid: std.c.uid_t,
        gid: std.c.gid_t,
    };
    var credentials: UCred = undefined;
    var len: std.c.socklen_t = @sizeOf(UCred);
    if (std.c.getsockopt(fd, std.c.SOL.SOCKET, std.c.SO.PEERCRED, &credentials, &len) != 0) return error.PeerCredentialsUnavailable;
    return .{
        .uid = @intCast(credentials.uid),
        .gid = @intCast(credentials.gid),
        .pid = if (credentials.pid >= 0) @intCast(credentials.pid) else null,
    };
}

extern "c" fn getpeereid(fd: std.c.fd_t, euid: *std.c.uid_t, egid: *std.c.gid_t) c_int;

fn readDarwinPeerCredentials(fd: std.posix.fd_t) !proto.Peer {
    var uid: std.c.uid_t = undefined;
    var gid: std.c.gid_t = undefined;
    if (getpeereid(fd, &uid, &gid) != 0) return error.PeerCredentialsUnavailable;
    return .{ .uid = @intCast(uid), .gid = @intCast(gid), .pid = null };
}

fn ipcMetadataName(header_name: []const u8) []const u8 {
    if (std.ascii.eqlIgnoreCase(header_name, "X-Meteorite-Validation-Domain")) return "meteorite.validation.domain";
    if (std.ascii.eqlIgnoreCase(header_name, "X-Meteorite-Validation-Field")) return "meteorite.validation.field";
    if (std.ascii.eqlIgnoreCase(header_name, "X-Meteorite-Validation-Reason")) return "meteorite.validation.reason";
    return header_name;
}

fn ipcResultCodeForStatus(status: u16, has_validation_metadata: bool) proto.ResultCode {
    if (has_validation_metadata) return .validation_error;
    return switch (status) {
        200...299, 304 => .ok,
        400 => .malformed_message,
        404 => .not_found,
        405 => .method_not_allowed,
        413, 414 => .payload_too_large,
        422 => .validation_error,
        429, 503 => .busy,
        else => if (status >= 500) .internal_error else .ok,
    };
}

test "validation headers become IPC validation metadata" {
    try std.testing.expectEqualStrings("meteorite.validation.domain", ipcMetadataName("X-Meteorite-Validation-Domain"));
    try std.testing.expectEqualStrings("meteorite.validation.field", ipcMetadataName("x-meteorite-validation-field"));
    try std.testing.expectEqualStrings("meteorite.validation.reason", ipcMetadataName("X-Meteorite-Validation-Reason"));
    try std.testing.expectEqualStrings("X-Other", ipcMetadataName("X-Other"));
}

test "HTTP validation status maps to IPC validation when diagnostics are present" {
    try std.testing.expectEqual(proto.ResultCode.malformed_message, ipcResultCodeForStatus(400, false));
    try std.testing.expectEqual(proto.ResultCode.validation_error, ipcResultCodeForStatus(400, true));
    try std.testing.expectEqual(proto.ResultCode.validation_error, ipcResultCodeForStatus(422, false));
}

test "IPC metadata content_type aliases content-type" {
    var req: Request = undefined;
    req.metadata_value = "content_type=application/json\n";
    try std.testing.expectEqualStrings("application/json", header(&req, "content-type") orelse return error.MissingContentType);
}

pub fn respondStatic(req: *Request, status: u16, content_type: []const u8, content_length: u64, cache_control: []const u8, etag: []const u8, content_encoding: ?[]const u8, body: []const u8, head_only: bool) !void {
    _ = content_length;
    _ = cache_control;
    _ = etag;
    _ = content_encoding;
    _ = head_only;
    try respondBytes(req, status, content_type, body);
}

pub fn respondRawOk(req: *Request) !void {
    try respondText(req, 200, "ok");
}
