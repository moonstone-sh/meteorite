pub const pattern = @import("meteorite_pattern").Pattern;
pub const matcher = pattern.compile(.{
    .start_state = {{start_state}},
    .dead_state = {{dead_state}},
    .class_count = {{class_count}},
    .class_map = &[_]u8{ {{class_map}} },
    .transitions = &[_]u8{ {{transitions}} },
    .accept = &[_]bool{ {{accept}} },
    .max_len = {{max_len}},
});
