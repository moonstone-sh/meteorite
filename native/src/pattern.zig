const std = @import("std");

pub fn DfaMatcher(comptime spec: anytype) type {
    return struct {
        pub fn match(input: []const u8) bool {
            if (@hasField(@TypeOf(spec), "max_input_bytes") and input.len > spec.max_input_bytes) return false;
            var state: u16 = spec.start_state;
            for (input) |byte| {
                const class = spec.class_map[byte];
                const idx: usize = @as(usize, state) * spec.class_count + class;
                state = spec.transition_table[idx];
                if (state == spec.dead_state) return false;
            }
            return spec.accept_table[state];
        }
    };
}

pub const patterns = struct {
    pub fn Dfa(comptime spec: anytype) type {
        return DfaMatcher(spec);
    }
};
