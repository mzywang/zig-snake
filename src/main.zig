const std = @import("std");
const posix = std.posix;
const Io = std.Io;

const min_board_width = 10;
const min_board_height = 4;
const tick_rate_ms = 150;
const ctrl_c = 0x03;

const Mode = enum {
    START,
    PLAYING,
    QUIT,
};

const Model = struct {
    mode: Mode,
    dot_col: usize, // 0..board_width, wraps around
    board_width: usize,
    board_height: usize,
};

const Action = union(enum) {
    tick,
    key_pressed,
    quit,
    resized: struct { width: usize, height: usize },
};

fn update(model: Model, action: Action) Model {
    return switch (action) {
        .tick => .{
            .mode = model.mode,
            .dot_col = if (model.mode == .PLAYING) (model.dot_col + 1) % model.board_width else model.dot_col,
            .board_width = model.board_width,
            .board_height = model.board_height,
        },
        .key_pressed => .{
            .mode = if (model.mode == .START) .PLAYING else model.mode,
            .dot_col = model.dot_col,
            .board_width = model.board_width,
            .board_height = model.board_height,
        },
        .quit => .{
            .mode = .QUIT,
            .dot_col = model.dot_col,
            .board_width = model.board_width,
            .board_height = model.board_height,
        },
        .resized => |size| .{
            .mode = model.mode,
            .dot_col = model.dot_col % size.width,
            .board_width = size.width,
            .board_height = size.height,
        },
    };
}

/// A small bounded mpsc-style channel: the event thread is the only
/// producer, `main`'s loop is the only consumer. `recv` blocks until an
/// event is available, mirroring `mpsc::Receiver::recv` from the ratatui
/// counter-app tutorial (https://ratatui.rs/tutorials/counter-app/_multiple-files/event/).
const EventChannel = struct {
    mutex: Io.Mutex = .init,
    cond: Io.Condition = .init,
    buffer: [64]Action = undefined,
    head: usize = 0,
    len: usize = 0,

    fn send(self: *EventChannel, io: Io, action: Action) void {
        self.mutex.lock(io) catch return;
        defer self.mutex.unlock(io);
        if (self.len == self.buffer.len) return; // drop if the consumer is backed up
        self.buffer[(self.head + self.len) % self.buffer.len] = action;
        self.len += 1;
        self.cond.signal(io);
    }

    fn recv(self: *EventChannel, io: Io) Action {
        self.mutex.lock(io) catch unreachable;
        defer self.mutex.unlock(io);
        while (self.len == 0) self.cond.wait(io, &self.mutex) catch unreachable;
        const action = self.buffer[self.head];
        self.head = (self.head + 1) % self.buffer.len;
        self.len -= 1;
        return action;
    }
};

/// Set by `handleSigWinch` (run on a signal, so it must stay minimal) and
/// consumed by `eventHandler`, which does the actual work of querying the
/// new size and sending it over the channel.
var resize_requested: std.atomic.Value(bool) = .init(false);

fn handleSigWinch(sig: posix.SIG, info: *const posix.siginfo_t, ctx_ptr: ?*anyopaque) callconv(.c) void {
    _ = sig;
    _ = info;
    _ = ctx_ptr;
    resize_requested.store(true, .monotonic);
}

/// Queries the current terminal dimensions via the TIOCGWINSZ ioctl,
/// returning the interior board size (terminal size minus the border),
/// clamped to a sane minimum.
fn queryBoardSize() struct { width: usize, height: usize } {
    var ws: posix.winsize = .{ .row = 0, .col = 0, .xpixel = 0, .ypixel = 0 };
    _ = std.c.ioctl(posix.STDOUT_FILENO, @intCast(std.c.T.IOCGWINSZ), &ws);
    return .{
        .width = @max(min_board_width, @as(usize, ws.col) -| 2),
        .height = @max(min_board_height, @as(usize, ws.row) -| 2),
    };
}

fn eventHandler(channel: *EventChannel, io: Io) void {
    var last_tick: Io.Clock.Timestamp = .now(io, .awake);

    while (true) {
        if (resize_requested.swap(false, .monotonic)) {
            const size = queryBoardSize();
            channel.send(io, .{ .resized = .{ .width = size.width, .height = size.height } });
        }

        const elapsed_ms = last_tick.untilNow(io).raw.toMilliseconds();
        if (elapsed_ms >= tick_rate_ms) {
            channel.send(io, .tick);
            last_tick = .now(io, .awake);
            continue;
        }

        var fds = [_]posix.pollfd{.{
            .fd = posix.STDIN_FILENO,
            .events = posix.POLL.IN,
            .revents = 0,
        }};
        const timeout_ms: i32 = @intCast(tick_rate_ms - elapsed_ms);
        const n = posix.poll(&fds, timeout_ms) catch 0;
        if (n > 0) {
            var buf: [64]u8 = undefined;
            const len = posix.read(posix.STDIN_FILENO, &buf) catch 0;
            if (len > 0) {
                const has_ctrl_c = std.mem.indexOfScalar(u8, buf[0..len], ctrl_c) != null;
                channel.send(io, if (has_ctrl_c) .quit else .key_pressed);
            }
        }
    }
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    // Large enough to hold a full frame (border + grid + newlines) for
    // any reasonably-sized terminal in one write, so each redraw reaches
    // the terminal in a single syscall instead of tearing across two.
    var stdout_buffer: [1 << 16]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout_writer = &stdout_file_writer.interface;

    const original_termios = try enterRawMode();
    defer posix.tcsetattr(posix.STDIN_FILENO, .FLUSH, original_termios) catch {};

    // Switch to the alternate screen buffer so frames don't pile up in the
    // terminal's normal scrollback (same trick vim/htop/less use). Restored
    // on exit below.
    try stdout_writer.writeAll("\x1b[?1049h\x1b[2J");
    defer stdout_writer.flush() catch {}; // declared first, so it runs *after* the write below
    defer stdout_writer.writeAll("\x1b[?1049l") catch {};

    const winch_action: posix.Sigaction = .{
        .handler = .{ .sigaction = handleSigWinch },
        .mask = posix.sigemptyset(),
        .flags = (posix.SA.SIGINFO | posix.SA.RESTART),
    };
    posix.sigaction(.WINCH, &winch_action, null);

    var channel: EventChannel = .{};
    _ = try std.Thread.spawn(.{}, eventHandler, .{ &channel, io });

    const initial_size = queryBoardSize();
    var model: Model = .{
        .mode = .START,
        .dot_col = 0,
        .board_width = initial_size.width,
        .board_height = initial_size.height,
    };
    while (true) {
        const action = channel.recv(io);
        model = update(model, action);

        if (model.mode == .QUIT) {
            try posix.tcsetattr(posix.STDIN_FILENO, .FLUSH, original_termios);
            break;
        }

        if (action == .resized) try stdout_writer.writeAll("\x1b[2J"); // clear stale content around the resized board
        try drawBoard(stdout_writer, model);
    }
}

/// Disables canonical mode, echo, and signal generation so keypresses
/// (including Ctrl-C) can be read as raw bytes instead of the terminal
/// acting on them. Returns the original settings to restore later.
fn enterRawMode() !posix.termios {
    const original = try posix.tcgetattr(posix.STDIN_FILENO);
    var raw = original;
    raw.lflag.ICANON = false;
    raw.lflag.ECHO = false;
    raw.lflag.ISIG = false;
    try posix.tcsetattr(posix.STDIN_FILENO, .FLUSH, raw);
    return original;
}

fn drawBoard(writer: *Io.Writer, model: Model) !void {
    try writer.writeAll("\x1b[H"); // move cursor home, then redraw
    const dot_col = 1 + model.dot_col;
    const dot_row = 1;

    for (0..model.board_height + 2) |row| {
        for (0..model.board_width + 2) |col| {
            const is_border = row == 0 or row == model.board_height + 1 or
                col == 0 or col == model.board_width + 1;
            const is_dot = row == dot_row and col == dot_col;
            try writer.writeByte(if (is_border) '#' else if (is_dot) '*' else '.');
        }
        try writer.writeByte('\n');
    }

    try writer.flush();
}
