const std = @import("std");
const types = @import("model.zig");

pub const BeforeHook = enum {
    CLEAR,
    NO_OP,
};

pub const DisplayUtils = struct {
    pub fn enterAlternateScreen(writer: *std.Io.Writer) !void {
        try writer.writeAll("\x1b[?1049h\x1b[2J");
        try writer.flush();
    }

    pub fn exitAlternateScreen(writer: *std.Io.Writer) void {
        writer.writeAll("\x1b[?1049l") catch {};
        writer.flush() catch {};
    }

    pub fn enterRawMode() !std.posix.termios {
        const original = try std.posix.tcgetattr(std.posix.STDIN_FILENO);
        var raw = original;
        raw.lflag.ICANON = false;
        raw.lflag.ECHO = false;
        raw.lflag.ISIG = false;
        try std.posix.tcsetattr(std.posix.STDIN_FILENO, .FLUSH, raw);
        return original;
    }

    pub fn exitRawMode(original: std.posix.termios) void {
        std.posix.tcsetattr(std.posix.STDIN_FILENO, .FLUSH, original) catch {};
    }

    pub fn queryBoardSize() types.BoardSize {
        var ws: std.posix.winsize = .{ .row = 0, .col = 0, .xpixel = 0, .ypixel = 0 };
        _ = std.c.ioctl(std.posix.STDOUT_FILENO, @intCast(std.c.T.IOCGWINSZ), &ws);

        const min_board_width = 10;
        const min_board_height = 4;

        return .{
            .width = @max(min_board_width, @as(usize, ws.col) -| 2),
            .height = @max(min_board_height, @as(usize, ws.row) -| 2),
        };
    }

    pub fn drawBoard(writer: *std.Io.Writer, model: types.Model, clear_board_before_drawing: BeforeHook) !void {
        if (clear_board_before_drawing == .CLEAR) try writer.writeAll("\x1b[2J"); // clear stale content around the resized board
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
};
