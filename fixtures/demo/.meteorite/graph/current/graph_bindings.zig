const std = @import("std");
const handlers = @import("meteorite_handlers");
const validators = @import("meteorite_validators");
const mt = @import("meteorite_ctx");

comptime {
}

pub const HandlerId = enum {
};

pub const ValidatorId = enum { none };

pub fn callHandler(comptime id: HandlerId, ctx: anytype) !void {
    return switch (id) {
    };
}

pub fn callRoute(comptime route_id: []const u8, raw_ctx: anytype) !void {
    @compileError("missing generated route handler binding for route `" ++ route_id ++ "`");
}

pub fn callValidator(comptime id: ValidatorId, value: []const u8) bool {
    _ = id;
    return validators.none(value);
}
