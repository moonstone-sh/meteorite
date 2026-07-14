const std = @import("std");
const server_validators = @import("validators.zig");
const request_parse = @import("request_parse.zig");

pub const ValidationError = struct {
    domain: []const u8,
    field: []const u8,
    reason: []const u8,
};

pub fn Validator(comptime graph: anytype, comptime backend: anytype) type {
    return struct {
        pub fn validateParam(comptime param: graph.ParamSpec, value: []const u8) bool {
            if (param.exact_len != 0 and value.len != param.exact_len) return false;
            if (param.max_len != 0 and value.len > param.max_len) return false;
            return switch (param.kind) {
                .string => true,
                .pattern => true,
                .slug => server_validators.isSlug(value),
                .u64 => server_validators.isUnsigned(value),
                .i32 => server_validators.isI32(value),
                .uuid => server_validators.isUuid(value),
                .hex => server_validators.isHex(value),
                .email => server_validators.isEmail(value),
                .token => server_validators.isToken(value),
                .bool => std.mem.eql(u8, value, "true") or std.mem.eql(u8, value, "false") or std.mem.eql(u8, value, "1") or std.mem.eql(u8, value, "0"),
            };
        }

        pub fn respondError(request: *backend.Request, validation_error: ValidationError) !void {
            const headers = [_]backend.Header{
                .{ .name = "X-Meteorite-Validation-Domain", .value = validation_error.domain },
                .{ .name = "X-Meteorite-Validation-Field", .value = validation_error.field },
                .{ .name = "X-Meteorite-Validation-Reason", .value = validation_error.reason },
            };
            try backend.respondTextWithHeaders(request, 400, "validation error", &headers);
        }

        pub fn validateQuery(comptime specs: []const graph.ParamSpec, allocator: std.mem.Allocator, request: *backend.Request) ?ValidationError {
            inline for (specs) |query_spec| {
                if (queryValue(allocator, request, query_spec.name)) |value| {
                    if (query_spec.pattern) |pattern| {
                        if (!graph.patterns.match(pattern, value)) return .{ .domain = "query", .field = query_spec.name, .reason = "invalid" };
                    }
                    if (!validateParam(query_spec, value)) return .{ .domain = "query", .field = query_spec.name, .reason = "invalid" };
                } else if (!query_spec.optional) {
                    return .{ .domain = "query", .field = query_spec.name, .reason = "missing" };
                }
            }
            return null;
        }

        pub fn validateHeaders(comptime specs: []const graph.ParamSpec, request: *backend.Request) ?ValidationError {
            inline for (specs) |header_spec| {
                if (backend.header(request, header_spec.name)) |value| {
                    if (header_spec.pattern) |pattern| {
                        if (!graph.patterns.match(pattern, value)) return .{ .domain = "header", .field = header_spec.name, .reason = "invalid" };
                    }
                    if (!validateParam(header_spec, value)) return .{ .domain = "header", .field = header_spec.name, .reason = "invalid" };
                } else if (!header_spec.optional) {
                    return .{ .domain = "header", .field = header_spec.name, .reason = "missing" };
                }
            }
            return null;
        }

        pub fn validateCookies(comptime specs: []const graph.ParamSpec, request: *backend.Request) ?ValidationError {
            const cookie_header = backend.header(request, "cookie");
            inline for (specs) |cookie_spec| {
                const lookup = if (cookie_header) |value| request_parse.cookieValue(value, cookie_spec.name) else request_parse.Lookup.missing;
                switch (lookup) {
                    .missing => if (!cookie_spec.optional) return .{ .domain = "cookie", .field = cookie_spec.name, .reason = "missing" },
                    .invalid => return .{ .domain = "cookie", .field = cookie_spec.name, .reason = "invalid" },
                    .value => |value| {
                        if (cookie_spec.pattern) |pattern| {
                            if (!graph.patterns.match(pattern, value)) return .{ .domain = "cookie", .field = cookie_spec.name, .reason = "invalid" };
                        }
                        if (!validateParam(cookie_spec, value)) return .{ .domain = "cookie", .field = cookie_spec.name, .reason = "invalid" };
                    },
                }
            }
            return null;
        }

        pub fn formContentTypeValid(request: *backend.Request) bool {
            const content_type = backend.header(request, "content-type") orelse return false;
            return request_parse.contentTypeIs(content_type, "application/x-www-form-urlencoded");
        }

        pub fn jsonContentTypeValid(request: *backend.Request) bool {
            const content_type = backend.header(request, "content-type") orelse return false;
            return request_parse.contentTypeIs(content_type, "application/json") or request_parse.contentTypeIs(content_type, "application/problem+json");
        }

        pub fn jsonBodyValidationDomain(comptime RequestType: type) []const u8 {
            if (comptime @hasField(RequestType, "frame_buffer")) return "json_body";
            return "json";
        }

        pub fn jsonValueValid(comptime json_spec: graph.ParamSpec, value: std.json.Value) bool {
            switch (json_spec.kind) {
                .string, .slug, .uuid, .hex, .email, .token, .pattern => {
                    const text = switch (value) {
                        .string => |text| text,
                        else => return false,
                    };
                    if (json_spec.pattern) |pattern| {
                        if (!graph.patterns.match(pattern, text)) return false;
                    }
                    return validateParam(json_spec, text);
                },
                .u64 => return switch (value) {
                    .integer => |number| number >= 0,
                    else => false,
                },
                .i32 => return switch (value) {
                    .integer => |number| number >= std.math.minInt(i32) and number <= std.math.maxInt(i32),
                    else => false,
                },
                .bool => return switch (value) {
                    .bool => true,
                    else => false,
                },
            }
        }

        pub fn validateJsonBody(comptime specs: []const graph.ParamSpec, request: *backend.Request, allocator: std.mem.Allocator) !?ValidationError {
            if (specs.len == 0) return null;
            const domain = comptime jsonBodyValidationDomain(backend.Request);
            if (!jsonContentTypeValid(request)) return null;
            const body = backend.readBody(request, allocator, 1024 * 1024) catch return .{ .domain = domain, .field = "body", .reason = "invalid" };
            var parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch return .{ .domain = domain, .field = "body", .reason = "invalid" };
            defer parsed.deinit();
            const object = switch (parsed.value) {
                .object => |object| object,
                else => return .{ .domain = domain, .field = "body", .reason = "invalid" },
            };
            inline for (specs) |json_spec| {
                if (object.get(json_spec.name)) |value| {
                    if (!jsonValueValid(json_spec, value)) return .{ .domain = domain, .field = json_spec.name, .reason = "invalid" };
                } else if (!json_spec.optional) {
                    return .{ .domain = domain, .field = json_spec.name, .reason = "missing" };
                }
            }
            return null;
        }

        pub fn validateFormBody(comptime specs: []const graph.ParamSpec, request: *backend.Request) !?ValidationError {
            if (specs.len == 0) return null;
            if (!formContentTypeValid(request)) return .{ .domain = "form", .field = "content-type", .reason = "invalid" };
            const body = backend.readBody(request, std.heap.page_allocator, 1024 * 1024) catch return .{ .domain = "form", .field = "body", .reason = "invalid" };
            inline for (specs) |form_spec| {
                switch (request_parse.formValue(body, form_spec.name)) {
                    .missing => if (!form_spec.optional) return .{ .domain = "form", .field = form_spec.name, .reason = "missing" },
                    .invalid => return .{ .domain = "form", .field = form_spec.name, .reason = "invalid" },
                    .value => |value| {
                        if (form_spec.pattern) |pattern| {
                            if (!graph.patterns.match(pattern, value)) return .{ .domain = "form", .field = form_spec.name, .reason = "invalid" };
                        }
                        if (!validateParam(form_spec, value)) return .{ .domain = "form", .field = form_spec.name, .reason = "invalid" };
                    },
                }
            }
            return null;
        }

        pub fn queryValue(allocator: std.mem.Allocator, request: *backend.Request, name: []const u8) ?[]const u8 {
            return request_parse.queryValue(allocator, backend.query(request), name);
        }

        pub fn queryAllValues(allocator: std.mem.Allocator, request: *backend.Request, name: []const u8) ?[][]const u8 {
            return request_parse.queryAllValues(allocator, backend.query(request), name);
        }
    };
}
