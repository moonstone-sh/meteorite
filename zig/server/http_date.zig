const std = @import("std");

/// Format a Unix timestamp as an HTTP Date header value (RFC 7231 IMF-fixdate).
/// Format: "Sun, 06 Nov 1994 08:49:37 GMT"
///
/// Uses a thread-local static buffer — callers should use the result immediately
/// or copy it before the next call on the same thread.
pub fn formatHttpDate(unix_seconds: i64) []const u8 {
    const epoch_seconds: std.time.epoch.EpochSeconds = .{ .secs = @intCast(unix_seconds) };
    const day_seconds = epoch_seconds.getDaySeconds();
    const epoch_day = epoch_seconds.getEpochDay();
    const year_day = epoch_day.calculateYearDay();
    const month_day = year_day.calculateMonthDay();

    const day_name = switch (epoch_day.day % 7) {
        0 => "Thu", // Jan 1 1970 was a Thursday
        1 => "Fri",
        2 => "Sat",
        3 => "Sun",
        4 => "Mon",
        5 => "Tue",
        6 => "Wed",
        else => unreachable,
    };
    const month_name = switch (month_day.month.numeric()) {
        1 => "Jan",
        2 => "Feb",
        3 => "Mar",
        4 => "Apr",
        5 => "May",
        6 => "Jun",
        7 => "Jul",
        8 => "Aug",
        9 => "Sep",
        10 => "Oct",
        11 => "Nov",
        12 => "Dec",
        else => unreachable,
    };

    return std.fmt.bufPrint(&date_buf, "{s}, {d:0>2} {s} {d} {d:0>2}:{d:0>2}:{d:0>2} GMT", .{
        day_name,
        month_day.day_index + 1,
        month_name,
        year_day.year,
        day_seconds.getHoursIntoDay(),
        day_seconds.getMinutesIntoHour(),
        day_seconds.getSecondsIntoMinute(),
    }) catch unreachable;
}

threadlocal var date_buf: [30]u8 = undefined;
