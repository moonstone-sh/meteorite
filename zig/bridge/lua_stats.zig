const std = @import("std");

pub const Stats = struct {
    lua_states_created: u64 = 0,
    lua_handler_refs_loaded: u64 = 0,
    lua_handler_calls: u64 = 0,
    lua_errors: u64 = 0,
    lua_state_reuse_hits: u64 = 0,
    lua_state_reuse_misses: u64 = 0,
    per_thread_state_count: u64 = 0,
};

const AtomicCounter = std.atomic.Value(u64);
const AtomicStats = struct {
    lua_states_created: AtomicCounter = AtomicCounter.init(0),
    lua_handler_refs_loaded: AtomicCounter = AtomicCounter.init(0),
    lua_handler_calls: AtomicCounter = AtomicCounter.init(0),
    lua_errors: AtomicCounter = AtomicCounter.init(0),
    lua_state_reuse_hits: AtomicCounter = AtomicCounter.init(0),
    lua_state_reuse_misses: AtomicCounter = AtomicCounter.init(0),
};

pub var stats = AtomicStats{};
pub var debug_shared_counter = AtomicCounter.init(0);
pub threadlocal var debug_worker_counter: u64 = 0;

pub fn inc(counter: *AtomicCounter) void {
    _ = counter.fetchAdd(1, .monotonic);
}

pub fn snapshot() Stats {
    const states = stats.lua_states_created.load(.monotonic);
    return .{
        .lua_states_created = states,
        .lua_handler_refs_loaded = stats.lua_handler_refs_loaded.load(.monotonic),
        .lua_handler_calls = stats.lua_handler_calls.load(.monotonic),
        .lua_errors = stats.lua_errors.load(.monotonic),
        .lua_state_reuse_hits = stats.lua_state_reuse_hits.load(.monotonic),
        .lua_state_reuse_misses = stats.lua_state_reuse_misses.load(.monotonic),
        .per_thread_state_count = states,
    };
}

