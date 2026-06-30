const std = @import("std");
const model = @import("../model.zig");
const common = @import("common.zig");

pub const AsciiDisplayUtils = struct {
    pub fn drawBoard(writer: *std.Io.Writer, m: model.Model) !void {
        return switch (m.mode) {
            .START => common.drawMessageScreen(writer, m, "Press any key to start"),
            .GAME_OVER => common.drawMessageScreen(writer, m, "Game over - press any key to restart"),
            else => drawPlayingBoard(writer, m),
        };
    }

    fn drawPlayingBoard(writer: *std.Io.Writer, m: model.Model) !void {
        try writer.writeAll("\x1b[H");
        const cell_width = @max(1, @as(usize, @intFromFloat(@round(m.cell_aspect_ratio))));
        const last_row = m.board_height + 1;

        for (0..m.board_height + 2) |row| {
            if (row == 0 or row == last_row) {
                try borderColor(writer, if (row == 0) "╔" else "╚");
                for (0..m.board_width * cell_width) |_| try borderColor(writer, "═");
                try borderColor(writer, if (row == 0) "╗" else "╝");
            } else {
                const board_row = row - 1;
                try borderColor(writer, "║");
                for (0..m.board_width) |col| {
                    const is_dot = board_row == m.dot_row and col == m.dot_col;
                    for (0..cell_width) |_| {
                        try writer.writeAll(if (is_dot) "\x1b[32;1m\u{2588}\x1b[0m" else "\x1b[2m\u{00b7}\x1b[0m");
                    }
                }
                try borderColor(writer, "║");
            }
            if (row != last_row) try writer.writeByte('\n');
        }

        try writer.flush();
    }

    fn borderColor(writer: *std.Io.Writer, glyph: []const u8) !void {
        try writer.writeAll("\x1b[36;1m");
        try writer.writeAll(glyph);
        try writer.writeAll("\x1b[0m");
    }
};
