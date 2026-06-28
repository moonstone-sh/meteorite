const std = @import("std");
const Io = std.Io;

/// Bounded connection pool with a fixed-size ring buffer queue.
/// Workers dequeue connections and serve them in a keep-alive loop.
///
/// The pool is started lazily on the first enqueue. Workers are detached
/// threads that run until the process exits. A shutdown flag could be
/// added for graceful drain in the future.
pub fn ConnectionPool(comptime Backend: type, comptime ServerType: type) type {
    return struct {
        const Self = @This();
        const Request = Backend.Request;
        const queue_limit = Backend.queue_limit;

        var mutex: Io.Mutex = .init;
        var available: Io.Condition = .init;
        var queue: [queue_limit]Request = undefined;
        var head: usize = 0;
        var tail: usize = 0;
        var depth: usize = 0;
        var started = std.atomic.Value(bool).init(false);

        pub fn workerCount() usize {
            if (Backend.configured_workers > 0) return @intCast(Backend.configured_workers);
            return std.Thread.getCpuCount() catch 1;
        }

        pub fn start(io: Io) !void {
            if (comptime !Backend.pooled_connections) return;
            if (started.swap(true, .acquire)) return;
            const count = workerCount();
            var i: usize = 0;
            while (i < count) : (i += 1) {
                const thread = try std.Thread.spawn(.{}, worker, .{io});
                Backend.threadSpawned();
                thread.detach();
            }
        }

        pub fn enqueue(io: Io, request: Request) bool {
            if (queue_limit == 0) return false;
            mutex.lockUncancelable(io);
            defer mutex.unlock(io);
            if (depth == queue_limit) return false;
            queue[tail] = request;
            tail = (tail + 1) % queue_limit;
            depth += 1;
            Backend.setQueueDepth(@intCast(depth));
            available.signal(io);
            return true;
        }

        fn dequeue(io: Io) Request {
            mutex.lockUncancelable(io);
            defer mutex.unlock(io);
            while (depth == 0) available.waitUncancelable(io, &mutex);
            const request = queue[head];
            head = (head + 1) % queue_limit;
            depth -= 1;
            Backend.setQueueDepth(@intCast(depth));
            return request;
        }

        fn worker(io: Io) void {
            while (true) {
                var request = dequeue(io);
                Backend.rebind(&request, io);
                ServerType.serveConnection(io, &request) catch |err| {
                    std.debug.print("pooled connection failed: {s}\n", .{@errorName(err)});
                    Backend.connectionError();
                    request.close(io);
                };
            }
        }
    };
}
