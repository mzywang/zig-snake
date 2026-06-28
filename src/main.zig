const std = @import("std");
const Io = std.Io;

const board_width = 20;
const board_height = 10;

const Model = struct {
    state: u8, // 1 or 2
};

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout_writer = &stdout_file_writer.interface;

    try stdout_writer.writeAll("\x1b[2J"); // clear the screen once at startup

    var model: Model = .{ .state = 1 };
    var tick: usize = 0;
    while (true) {
        try stdout_writer.writeAll("\x1b[H"); // move cursor home, then redraw
        try drawBoard(stdout_writer, model, tick);
        try stdout_writer.flush();

        try Io.sleep(io, .fromMilliseconds(150), .awake);
        tick += 1;
        model.state = if (model.state == 1) 2 else 1;
    }
}

fn drawBoard(writer: *Io.Writer, model: Model, tick: usize) !void {
    const dot_col = 1 + (tick % board_width);
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
