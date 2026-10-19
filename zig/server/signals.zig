const platform = if (@import("builtin").os.tag == .windows) @import("signals_windows.zig") else @import("signals_posix.zig");
pub const installHandlers = platform.installHandlers;
pub const isShutdownRequested = platform.isShutdownRequested;
pub const requestShutdown = platform.requestShutdown;
pub const waitForAcceptable = platform.waitForAcceptable;
