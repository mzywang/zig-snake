const std = @import("std");
const posix = std.posix;
const Io = std.Io;

const board_width = 20;
const board_height = 10;

const Model = struct {
    state: u8, // 1 or 2
    tick: usize,
};

const Action = enum {
    tick,
    key_pressed,
};

fn update(model: Model, action: Action) Model {
    return switch (action) {
        .tick => .{ .state = model.state, .tick = model.tick + 1 },
        .key_pressed => .{
            .state = if (model.state == 1) 2 else model.state,
            .tick = model.tick,
        },
    };
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout_writer = &stdout_file_writer.interface;

    const original_termios = try enterRawMode();
    defer posix.tcsetattr(posix.STDIN_FILENO, .FLUSH, original_termios) catch {};

    try stdout_writer.writeAll("\x1b[2J"); // clear the screen once at startup

    var model: Model = .{ .state = 1, .tick = 0 };
    while (true) {
        try stdout_writer.writeAll("\x1b[H"); // move cursor home, then redraw
        try drawBoard(stdout_writer, model);
        try stdout_writer.flush();

        try Io.sleep(io, .fromMilliseconds(150), .awake);

        if (try keyWasPressed()) model = update(model, .key_pressed);
        model = update(model, .tick);
    }
}

/// Disables canonical mode and echo so keypresses can be detected without
/// the user pressing Enter, and returns the original settings to restore later.
fn enterRawMode() !posix.termios {
    const original = try posix.tcgetattr(posix.STDIN_FILENO);
    var raw = original;
    raw.lflag.ICANON = false;
    raw.lflag.ECHO = false;
    try posix.tcsetattr(posix.STDIN_FILENO, .FLUSH, raw);
    return original;
}

/// Non-blocking check for whether a key is waiting on stdin. Consumes the
/// byte if present, since we don't care which key was pressed.
fn keyWasPressed() !bool {
    var fds = [_]posix.pollfd{.{
        .fd = posix.STDIN_FILENO,
        .events = posix.POLL.IN,
        .revents = 0,
    }};
    const n = try posix.poll(&fds, 0);
    if (n == 0) return false;

    var discard: [1]u8 = undefined;
    _ = posix.read(posix.STDIN_FILENO, &discard) catch {};
    return true;
}

fn drawBoard(writer: *Io.Writer, model: Model) !void {
    const dot_col = 1 + (model.tick % board_width);
    const dot_row: usize = switch (model.state) {
        1 => 1,
        2 => 2,
        else => unreachable,
    };

    for (0..board_height + 2) |row| {
        for (0..board_width + 2) |col| {
            const is_border = row == 0 or row == board_height + 1 or
                col == 0 or col == board_width + 1;
            const is_dot = row == dot_row and col == dot_col;
            try writer.writeByte(if (is_border) '#' else if (is_dot) '*' else '.');
        }
        try writer.writeByte('\n');
    }
}
