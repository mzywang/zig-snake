const std = @import("std");
const model = @import("../model.zig");
const common = @import("common.zig");

pub const AsciiDisplayUtils = struct {
    pub const OverlayDrawFn = *const fn (writer: *std.Io.Writer, m: model.Model, message: []const u8) anyerror!common.MessageRegion;

    pub fn drawAsciiFrame(writer: *std.Io.Writer, m: model.Model, drawMessageOverlay: OverlayDrawFn) !void {
        try drawBorder(writer, m);

        switch (m.mode) {
            .PLAYING => try drawDot(writer, m),
            .START => _ = try drawMessageOverlay(writer, m, "Press any key to start"),
            .GAME_OVER => _ = try drawMessageOverlay(writer, m, "Game over - press any key to restart"),
            .QUIT => {},
        }

        try writer.flush();
    }

    fn drawBorder(writer: *std.Io.Writer, m: model.Model) !void {
        try writer.writeAll("\x1b[H");
        const last_row = m.board_height + 1;
        const last_col = m.board_width + 1;

        for (0..m.board_height + 2) |row| {
            for (0..m.board_width + 2) |col| {
                const is_border = row == 0 or row == last_row or col == 0 or col == last_col;
                try writer.writeByte(if (is_border) '#' else '.');
            }
            if (row != last_row) try writer.writeByte('\n');
        }
    }

    fn drawDot(writer: *std.Io.Writer, m: model.Model) !void {
        try writer.print("\x1b[{d};{d}H*", .{ m.dot_row + 2, m.dot_col + 2 });
    }
};
