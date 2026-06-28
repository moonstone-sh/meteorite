pub fn route(comptime graph: type) graph.Route {
    const data = struct {
        const segments = [_]graph.Segment{{segments}}
        };
        const query = [_]graph.ParamSpec{{query}}
        };
        const params = [_]graph.ParamSpec{{params}}
        };
        const capabilities = [_]graph.CapabilityRef{{capabilities}}
        };
        const static_assets = [_]graph.StaticAsset{{static_assets}}
        };
        const scope_chain = [_]graph.ScopeRef{{scope_chain}}
        };
        const scope_plugins = [_][]const u8{{scope_plugins}}
        };
        const scope_context = [_]graph.ScopeContextRef{{scope_context}}
        };
    };
    return .{ .id = {{id}}, .method = .{{method}}, .raw_path = {{raw_path}}, .path = &data.segments, .params = &data.params, .query = &data.query, .memory = {{memory}}, .max_body_bytes = {{max_body_bytes}}, .request_arena_bytes = {{request_arena_bytes}}, .handler = {{handler}}, .runtime = {{runtime}}, .execution = {{execution}}, .capabilities = &data.capabilities, .scope = {{scope}} };
}
