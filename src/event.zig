const std = @import("std");
const model = @import("model.zig");

pub const EventHandlerUtils = struct {
    /// A bounded mpsc channel (single producer: the event thread; single
    /// consumer: `main`'s loop), modeled after `mpsc::channel` in the ratatui
    /// counter-app tutorial (https://ratatui.rs/tutorials/counter-app/_multiple-files/event/).
    pub const EventChannel = struct {
        mutex: std.Io.Mutex = .init,
        cond: std.Io.Condition = .init,
        buffer: [64]model.Action = undefined,
        head: usize = 0,
        len: usize = 0,

        pub fn send(self: *EventChannel, io: std.Io, action: model.Action) void {
            self.mutex.lock(io) catch return;
            defer self.mutex.unlock(io);
            // drop if the consumer is backed up
            if (self.len == self.buffer.len) return;
            self.buffer[(self.head + self.len) % self.buffer.len] = action;
            self.len += 1;
            self.cond.signal(io);
        }

        pub fn recv(self: *EventChannel, io: std.Io) model.Action {
            self.mutex.lock(io) catch unreachable;
            defer self.mutex.unlock(io);
            while (self.len == 0) self.cond.wait(io, &self.mutex) catch unreachable;
            const action = self.buffer[self.head];
            self.head = (self.head + 1) % self.buffer.len;
            self.len -= 1;
            return action;
        }
    };

    pub fn makeWindowChangeRegistrar(comptime resize_requested: *std.atomic.Value(bool)) fn () void {
        return struct {
            fn register() void {
                const handleSigWinch = struct {
                    fn handle(sig: std.posix.SIG, info: *const std.posix.siginfo_t, ctx_ptr: ?*anyopaque) callconv(.c) void {
                        _ = sig;
                        _ = info;
                        _ = ctx_ptr;
                        resize_requested.store(true, .monotonic);
                    }
                }.handle;

                const winch_action: std.posix.Sigaction = .{
                    .handler = .{ .sigaction = handleSigWinch },
                    .mask = std.posix.sigemptyset(),
                    .flags = (std.posix.SA.SIGINFO | std.posix.SA.RESTART),
                };
                std.posix.sigaction(.WINCH, &winch_action, null);
            }
        }.register;
    }

    fn resizeRequest(size: model.BoardSize) model.Action {
        return .{ .resized = size };
    }

    fn sendTickIfDue(last_tick: *std.Io.Clock.Timestamp, channel: *EventChannel, io: std.Io, tick_rate_ms: i64) ?i64 {
        const elapsed_ms = last_tick.untilNow(io).raw.toMilliseconds();
        if (elapsed_ms >= tick_rate_ms) {
            channel.send(io, .tick);
            last_tick.* = .now(io, .awake);
            return null;
        }
        return elapsed_ms;
    }

    fn directionFromKeys(buf: []const u8) ?model.Direction {
        var i: usize = 0;
        while (i < buf.len) : (i += 1) {
            switch (buf[i]) {
                'w', 'W' => return .up,
                's', 'S' => return .down,
                'a', 'A' => return .left,
                'd', 'D' => return .right,
                0x1b => if (i + 2 < buf.len and buf[i + 1] == '[') {
                    switch (buf[i + 2]) {
                        'A' => return .up,
                        'B' => return .down,
                        'C' => return .right,
                        'D' => return .left,
                        else => {},
                    }
                },
                else => {},
            }
        }
        return null;
    }

    fn pollForStdin(channel: *EventChannel, io: std.Io, timeout_ms: i32) void {
        var fds = [_]std.posix.pollfd{.{
            .fd = std.posix.STDIN_FILENO,
            .events = std.posix.POLL.IN,
            .revents = 0,
        }};
        const n = std.posix.poll(&fds, timeout_ms) catch 0;
        if (n == 0) return;

        var buf: [64]u8 = undefined;
        const len = std.posix.read(std.posix.STDIN_FILENO, &buf) catch 0;
        if (len == 0) return;

        const ctrl_c = 0x03;
        const has_ctrl_c = std.mem.indexOfScalar(u8, buf[0..len], ctrl_c) != null;
        if (has_ctrl_c) {
            channel.send(io, .quit);
            return;
        }

        channel.send(io, .{ .key_pressed = directionFromKeys(buf[0..len]) });
    }

    pub fn registerEventHandler(
        resize_requested: *std.atomic.Value(bool),
        channel: *EventChannel,
        io: std.Io,
        queryBoardSize: fn () model.BoardSize,
    ) !void {
        _ = try std.Thread.spawn(.{}, eventHandler, .{
            resize_requested,
            channel,
            io,
            queryBoardSize,
        });
    }

    fn eventHandler(
        resize_requested: *std.atomic.Value(bool),
        channel: *EventChannel,
        io: std.Io,
        queryBoardSize: fn () model.BoardSize,
    ) void {
        const tick_rate_ms = model.tick_rate_ms;
        var last_tick: std.Io.Clock.Timestamp = .now(io, .awake);

        while (true) {
            if (resize_requested.swap(false, .monotonic)) {
                channel.send(io, EventHandlerUtils.resizeRequest(queryBoardSize()));
            }

            const elapsed_ms = EventHandlerUtils.sendTickIfDue(&last_tick, channel, io, tick_rate_ms) orelse continue;
            const timeout_ms: i32 = @intCast(tick_rate_ms - elapsed_ms);
            EventHandlerUtils.pollForStdin(channel, io, timeout_ms);
        }
    }
};
