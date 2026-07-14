const std = @import("std");

pub fn Response(comptime backend: anytype, comptime protocol: anytype, comptime build_info: anytype) type {
    return struct {
        pub fn resultCodeForStatus(status: u16) protocol.ResultCode {
            return switch (status) {
                200...299 => .ok,
                404 => .not_found,
                405 => .method_not_allowed,
                413 => .payload_too_large,
                422 => .validation_error,
                429 => .busy,
                else => if (status >= 500) .internal_error else .ok,
            };
        }

        pub fn text(ctx: anytype, status: u16, response_body: []const u8) !void {
            if (response_body.len > ctx.route.memory.max_response_bytes) {
                try stageBytes(ctx, 500, "text/plain; charset=utf-8", "response too large", &.{});
                return;
            }
            try stageBytes(ctx, status, "text/plain; charset=utf-8", response_body, &.{});
        }

        pub fn textWithHeaders(ctx: anytype, status: u16, response_body: []const u8, headers: []const backend.Header) !void {
            try bytesWithHeaders(ctx, status, "text/plain; charset=utf-8", response_body, headers);
        }

        pub fn bytes(ctx: anytype, status: u16, content_type: []const u8, response_body: []const u8) !void {
            if (response_body.len > ctx.route.memory.max_response_bytes) {
                try stageBytes(ctx, 500, "text/plain; charset=utf-8", "response too large", &.{});
                return;
            }
            try stageBytes(ctx, status, content_type, response_body, &.{});
        }

        pub fn bytesWithHeaders(ctx: anytype, status: u16, content_type: []const u8, response_body: []const u8, headers: []const backend.Header) !void {
            if (headers.len > 0 and !build_info.capability_http_headers) return error.HttpHeadersUnavailable;
            if (response_body.len > ctx.route.memory.max_response_bytes) {
                try stageBytes(ctx, 500, "text/plain; charset=utf-8", "response too large", &.{});
                return;
            }
            try protocol.validateResponseHeaders(headers);
            try stageBytes(ctx, status, content_type, response_body, headers);
        }

        pub fn responseHeader(ctx: anytype, name: []const u8, value: []const u8) !void {
            if (!build_info.capability_http_headers) return error.HttpHeadersUnavailable;
            try protocol.validateResponseHeader(name, value);
            if (ctx.response_header_count >= ctx.response_headers.len) return error.TooManyResponseHeaders;
            ctx.response_headers[ctx.response_header_count] = .{ .name = try ctx.allocator.dupe(u8, name), .value = try ctx.allocator.dupe(u8, value) };
            ctx.response_header_count += 1;
        }

        pub fn stageBytes(ctx: anytype, status: u16, content_type: []const u8, response_body: []const u8, headers: []const backend.Header) !void {
            if (response_body.len > ctx.route.memory.max_response_bytes) return error.ResponseTooLarge;
            ctx.response_status = status;
            ctx.response_content_type = try ctx.allocator.dupe(u8, content_type);
            ctx.response_body = try ctx.allocator.dupe(u8, response_body);
            ctx.response_header_count = 0;
            for (headers) |header_item| try responseHeader(ctx, header_item.name, header_item.value);
            ctx.responded = true;
            ctx.response_staged = true;
        }

        pub fn commitResponse(ctx: anytype) !void {
            if (!ctx.response_staged) return;
            const response = meteoriteResponse(ctx);
            try backend.respondBytesWithHeaders(ctx.request, response.status orelse ctx.response_status, response.content_type, response.body, response.headers);
            ctx.response_staged = false;
            ctx.response_committed = true;
        }

        pub fn meteoriteResponse(ctx: anytype) protocol.MeteoriteResponse {
            return .{
                .result = resultCodeForStatus(ctx.response_status),
                .status = ctx.response_status,
                .content_type = ctx.response_content_type,
                .metadata = &.{},
                .headers = ctx.response_headers[0..ctx.response_header_count],
                .body = ctx.response_body,
                .close_policy = if (ctx.request.close_after_response) .close_after_response else .keep_open,
            };
        }

        pub fn json(ctx: anytype, status: u16, response_body: []const u8) !void {
            try bytes(ctx, status, "application/json", response_body);
        }

        pub fn jsonWithHeaders(ctx: anytype, status: u16, response_body: []const u8, headers: []const backend.Header) !void {
            try bytesWithHeaders(ctx, status, "application/json", response_body, headers);
        }

        pub fn empty(ctx: anytype, status: u16) !void {
            try bytes(ctx, status, "text/plain; charset=utf-8", "");
        }

        pub fn emptyWithHeaders(ctx: anytype, status: u16, headers: []const backend.Header) !void {
            try bytesWithHeaders(ctx, status, "text/plain; charset=utf-8", "", headers);
        }

        pub fn redirect(ctx: anytype, status: u16, location: []const u8) !void {
            if (!build_info.capability_redirects) return error.RedirectsUnavailable;
            if (!protocol.isRedirectStatus(status)) return error.InvalidRedirectStatus;
            try protocol.validateRedirectLocation(location);
            try emptyWithHeaders(ctx, status, &.{.{ .name = "Location", .value = location }});
        }

        pub fn setCookie(buffer: []u8, name: []const u8, value: []const u8, options: protocol.CookieOptions) !backend.Header {
            if (!build_info.capability_cookies) return error.CookiesUnavailable;
            return .{ .name = "Set-Cookie", .value = try protocol.buildSetCookie(buffer, name, value, options) };
        }
    };
}
