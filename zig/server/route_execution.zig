const std = @import("std");

pub fn Execution(comptime graph: anytype, comptime lua_runtime: anytype, comptime build_info: anytype, comptime serveFileHandler: anytype, comptime serveDirHandler: anytype) type {
    return struct {
        pub fn callLuaHandler(comptime route: graph.Route, comptime handler: anytype, ctx: anytype) !void {
            return lua_runtime.call(.{
                .id = handler.id,
                .bench_route = route.raw_path,
                .path = switch (@TypeOf(handler)) {
                    graph.InlineLuaHandler => handler.chunk_path,
                    graph.LuaFileHandler => handler.path,
                    else => @compileError("unsupported Lua handler type"),
                },
                .nparams = if (@TypeOf(handler) == graph.InlineLuaHandler) handler.nparams else 1,
                .arg_mode = if (@TypeOf(handler) == graph.InlineLuaHandler) handler.arg_mode else .request_table,
            }, ctx);
        }

        pub fn executeScopePlugins(comptime route: graph.Route, ctx: anytype) !bool {
            inline for (route.scope.plugins) |plugin_id| {
                if (comptime graph.pluginById(plugin_id)) |plugin| {
                    const short_circuit = try executePlugin(plugin, ctx);
                    if (short_circuit) return true;
                }
            }
            return false;
        }

        pub fn executePlugin(comptime plugin: graph.PluginDescriptor, ctx: anytype) !bool {
            switch (plugin.handler) {
                .none => return false,
                .inline_lua => |handler| {
                    const short_circuit = try lua_runtime.callPlugin(handler, ctx);
                    if (short_circuit) return true;
                },
                .lua_file => |handler| {
                    const short_circuit = try lua_runtime.callPlugin(handler, ctx);
                    if (short_circuit) return true;
                },
                .zig_symbol => |handler| {
                    _ = handler;
                },
            }
            return false;
        }

        pub fn respondRouteError(ctx: anytype, err: anyerror) !bool {
            std.debug.print("route error boundary for {s} {s}: {s}\n", .{ @tagName(ctx.route.method), ctx.route.raw_path, @errorName(err) });
            ctx.request.close_after_response = true;
            if (ctx.response_committed) return true;
            const body = switch (err) {
                error.HttpHeadersUnavailable => "backend capability unavailable: http_headers",
                error.CookiesUnavailable => "backend capability unavailable: cookies",
                error.RedirectsUnavailable => "backend capability unavailable: redirects",
                else => "internal server error",
            };
            if (build_info.capability_http_headers) {
                try ctx.textWithHeaders(500, body, &.{.{ .name = "X-Meteorite-Error-Boundary", .value = "route" }});
            } else {
                try ctx.text(500, body);
            }
            try ctx.commitResponse();
            return true;
        }

        pub fn respondRouteStageError(comptime stage: graph.PipelineStage, ctx: anytype, err: anyerror) !bool {
            std.debug.print(
                "pipeline stage error route_id={s} route={s} stage_id={s} kind={s} strat={s} phase={s} path={s} symbol={s} owner={s} error={s}\n",
                .{
                    ctx.route.id,
                    ctx.route.raw_path,
                    stage.id,
                    @tagName(stage.kind),
                    @tagName(stage.strat),
                    @tagName(stage.phase),
                    stage.path,
                    stage.symbol,
                    stage.owner,
                    @errorName(err),
                },
            );
            return respondRouteError(ctx, err);
        }

        pub fn executeRouteBody(comptime route: graph.Route, ctx: anytype, allocator: std.mem.Allocator, io: anytype, request: anytype, captures: anytype) !bool {
            if (route.pipeline.len > 0) {
                inline for (route.pipeline) |stage| {
                    switch (stage.strat) {
                        .inline_lua => {
                            if (stage.kind == .handle) {
                                switch (route.handler) {
                                    .inline_lua => |handler| callLuaHandler(route, handler, ctx) catch |err| return respondRouteStageError(stage, ctx, err),
                                    .lua_file => |handler| callLuaHandler(route, handler, ctx) catch |err| return respondRouteStageError(stage, ctx, err),
                                    else => {},
                                }
                            }
                        },
                        .lua => {
                            if (stage.kind == .handle) {
                                switch (route.handler) {
                                    .inline_lua => |handler| callLuaHandler(route, handler, ctx) catch |err| return respondRouteStageError(stage, ctx, err),
                                    .lua_file => |handler| callLuaHandler(route, handler, ctx) catch |err| return respondRouteStageError(stage, ctx, err),
                                    else => {},
                                }
                            }
                        },
                        .zig => {
                            if (stage.kind == .handle) {
                                graph.bindings.callRoute(route.id, ctx) catch |err| return respondRouteStageError(stage, ctx, err);
                            }
                            if (stage.kind == .hook and stage.phase == .post_handler) {
                                graph.bindings.callHandlerBySymbol(stage.symbol, ctx) catch |err| return respondRouteStageError(stage, ctx, err);
                            }
                        },
                        .rust => {},
                    }
                }
            } else {
                switch (route.handler) {
                    .zig_symbol, .zig_file => graph.bindings.callRoute(route.id, ctx) catch |err| return respondRouteError(ctx, err),
                    .inline_lua => |handler| callLuaHandler(route, handler, ctx) catch |err| return respondRouteError(ctx, err),
                    .lua_file => |handler| callLuaHandler(route, handler, ctx) catch |err| return respondRouteError(ctx, err),
                    .file => |handler| try serveFileHandler(handler, allocator, io, request),
                    .dir => |handler| try serveDirHandler(handler, allocator, io, request, captures),
                }
            }
            return false;
        }
    };
}
