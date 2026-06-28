const std = @import("std");
const Io = std.Io;

const board_width = 20;
const board_height = 10;

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout_writer = &stdout_file_writer.interface;

    try drawBoard(stdout_writer);

    try stdout_writer.flush(); // Don't forget to flush!
}

fn drawBoard(writer: *Io.Writer) !void {
    for (0..board_height + 2) |row| {
        for (0..board_width + 2) |col| {
            const is_border = row == 0 or row == board_height + 1 or
                col == 0 or col == board_width + 1;
            try writer.writeByte(if (is_border) '#' else '.');
        }
        try writer.writeByte('\n');
    }
}
