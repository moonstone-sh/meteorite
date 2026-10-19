const std = @import("std");
const windows = std.os.windows;
var shutdown = std.atomic.Value(bool).init(false);
extern "kernel32" fn SetConsoleCtrlHandler(handler: ?*const fn (u32) callconv(.winapi) c_int, add: c_int) callconv(.winapi) c_int;
extern "kernel32" fn ExitProcess(code: u32) callconv(.winapi) noreturn;
fn handler(signal: u32) callconv(.winapi) c_int {
    if (signal > 6) return 0;
    if (shutdown.swap(true, .acq_rel)) ExitProcess(130);
    return 1;
}
pub fn installHandlers() void {
    if (SetConsoleCtrlHandler(handler, 1) == 0) std.debug.print("meteorite: cannot install Windows console handler\n", .{});
}
pub fn isShutdownRequested() bool {
    return shutdown.load(.acquire);
}
pub fn requestShutdown() void {
    shutdown.store(true, .release);
}
// Zig 0.16 creates AFD sockets directly. Poll that same handle rather than
// passing it through Winsock or canceling Zig's in-flight accept operation.
// The finite NT poll timeout bounds idle-console shutdown latency to 100 ms.
const PollHandle = extern struct { handle: windows.HANDLE, events: u32, status: windows.NTSTATUS };
const Poll = extern struct { timeout: i64, count: u32, exclusive: u32, handles: [1]PollHandle };
pub fn waitForAcceptable(socket: std.Io.net.Socket.Handle) bool {
    var event: windows.HANDLE = undefined;
    if (windows.ntdll.NtCreateEvent(&event, @bitCast(@as(u32, 0x1f0003)), null, .Synchronization, .FALSE) != .SUCCESS) {
        std.debug.print("meteorite: cannot create Windows accept poll event\n", .{});
        return false;
    }
    defer windows.CloseHandle(event);
    while (!isShutdownRequested()) {
        var poll: Poll = .{ .timeout = -1_000_000, .count = 1, .exclusive = 0, .handles = .{.{ .handle = socket, .events = 0x80, .status = .SUCCESS }} };
        var status: windows.IO_STATUS_BLOCK = undefined;
        const result = windows.ntdll.NtDeviceIoControlFile(socket, event, null, null, &status, windows.IOCTL.AFD.POLL, &poll, @sizeOf(Poll), &poll, @sizeOf(Poll));
        if (result == .PENDING) {
            if (windows.ntdll.NtWaitForSingleObject(event, .FALSE, null) != .SUCCESS) return false;
        } else if (result != .SUCCESS and result != .TIMEOUT) {
            std.debug.print("meteorite: Windows accept poll failed: {t}\n", .{result});
            return false;
        }
        if (isShutdownRequested()) return false;
        if (result == .TIMEOUT or status.u.Status == .TIMEOUT) continue;
        if (status.u.Status != .SUCCESS) {
            std.debug.print("meteorite: Windows accept poll completion failed: {t}\n", .{status.u.Status});
            return false;
        }
        if (poll.count != 0 and poll.handles[0].events & 0x80 != 0) return true;
    }
    return false;
}
