const std = @import("std");
const posix = std.posix;
const Io = std.Io;

const board_width = 20;
const board_height = 10;
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
};

const Action = enum {
    tick,
    key_pressed,
    quit,
};

fn update(model: Model, action: Action) Model {
    return switch (action) {
        .tick => .{
            .mode = model.mode,
            .dot_col = if (model.mode == .PLAYING) (model.dot_col + 1) % board_width else model.dot_col,
        },
        .key_pressed => .{
            .mode = if (model.mode == .START) .PLAYING else model.mode,
            .dot_col = model.dot_col,
        },
        .quit => .{ .mode = .QUIT, .dot_col = model.dot_col },
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

fn eventHandler(channel: *EventChannel, io: Io) void {
    while (true) {
        var fds = [_]posix.pollfd{.{
            .fd = posix.STDIN_FILENO,
            .events = posix.POLL.IN,
            .revents = 0,
        }};
        const n = posix.poll(&fds, tick_rate_ms) catch 0;
        if (n > 0) {
            var byte: [1]u8 = undefined;
            _ = posix.read(posix.STDIN_FILENO, &byte) catch {};
            channel.send(io, if (byte[0] == ctrl_c) .quit else .key_pressed);
        } else {
            channel.send(io, .tick);
        }
    }
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout_writer = &stdout_file_writer.interface;

    const original_termios = try enterRawMode();
    defer posix.tcsetattr(posix.STDIN_FILENO, .FLUSH, original_termios) catch {};

    try stdout_writer.writeAll("\x1b[2J"); // clear the screen once at startup

    var channel: EventChannel = .{};
    _ = try std.Thread.spawn(.{}, eventHandler, .{ &channel, io });

    var model: Model = .{ .mode = .START, .dot_col = 0 };
    while (true) {
        const action = channel.recv(io);
        model = update(model, action);

        if (model.mode == .QUIT) {
            try posix.tcsetattr(posix.STDIN_FILENO, .FLUSH, original_termios);
            break;
        }

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

    for (0..board_height + 2) |row| {
        for (0..board_width + 2) |col| {
            const is_border = row == 0 or row == board_height + 1 or
                col == 0 or col == board_width + 1;
            const is_dot = row == dot_row and col == dot_col;
            try writer.writeByte(if (is_border) '#' else if (is_dot) '*' else '.');
        }
        try writer.writeByte('\n');
    }

    try writer.flush();
}
