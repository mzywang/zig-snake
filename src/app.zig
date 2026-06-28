const std = @import("std");
const model = @import("model.zig");

pub const BeforeHook = enum {
    CLEAR,
    NO_OP,
    QUIT,
};

pub const AppUtils = struct {
    pub const Session = struct {
        model: model.Model,
        stdout: Stdout,
    };

    pub const Stdout = struct {
        buffer: [1 << 16]u8 = undefined,
        file_writer: std.Io.File.Writer = undefined,

        fn init(self: *Stdout, io: std.Io) void {
            self.file_writer = .init(.stdout(), io, &self.buffer);
        }

        fn writer(self: *Stdout) *std.Io.Writer {
            return &self.file_writer.interface;
        }

        pub fn setup(self: *Stdout, io: std.Io) *std.Io.Writer {
            self.init(io);
            return self.writer();
        }
    };

    pub fn enterAlternateScreen(writer: *std.Io.Writer) !void {
        try writer.writeAll("\x1b[?1049h\x1b[2J\x1b[?25l");
        try writer.flush();
    }

    pub fn exitAlternateScreen(writer: *std.Io.Writer) void {
        writer.writeAll("\x1b[?25h\x1b[?1049l") catch {};
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

    pub fn queryBoardSize() model.BoardSize {
        var ws: std.posix.winsize = .{ .row = 0, .col = 0, .xpixel = 0, .ypixel = 0 };
        _ = std.c.ioctl(std.posix.STDOUT_FILENO, @intCast(std.c.T.IOCGWINSZ), &ws);

        const min_board_width = 10;
        const min_board_height = 4;

        return .{
            .width = @max(min_board_width, @as(usize, ws.col) -| 2),
            .height = @max(min_board_height, @as(usize, ws.row) -| 2),
            .cell_aspect_ratio = queryCellAspectRatio(ws),
        };
    }

    fn queryCellAspectRatio(ws: std.posix.winsize) f64 {
        if (ws.col == 0 or ws.row == 0 or ws.xpixel == 0 or ws.ypixel == 0) {
            return model.default_cell_aspect_ratio;
        }

        const cell_width = @as(f64, @floatFromInt(ws.xpixel)) / @as(f64, @floatFromInt(ws.col));
        const cell_height = @as(f64, @floatFromInt(ws.ypixel)) / @as(f64, @floatFromInt(ws.row));
        return cell_height / cell_width;
    }

    pub fn drawBoard(writer: *std.Io.Writer, m: model.Model) !void {
        if (m.mode == .START) return drawStartScreen(writer, m);
        return drawPlayingBoard(writer, m);
    }

    fn drawPlayingBoard(writer: *std.Io.Writer, m: model.Model) !void {
        try writer.writeAll("\x1b[H");
        const dot_col = 1 + m.dot_col;
        const dot_row = 1 + m.dot_row;
        const last_row = m.board_height + 1;
        const last_col = m.board_width + 1;

        for (0..m.board_height + 2) |row| {
            for (0..m.board_width + 2) |col| {
                const is_dot = row == dot_row and col == dot_col;

                if (row == 0 or row == last_row or col == 0 or col == last_col) {
                    try borderColor(writer, borderGlyph(row, col, last_row, last_col));
                } else if (is_dot) {
                    try writer.writeAll("\x1b[32;1m\u{2588}\x1b[0m");
                } else {
                    try writer.writeAll("\x1b[2m\u{00b7}\x1b[0m");
                }
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

    fn borderGlyph(row: usize, col: usize, last_row: usize, last_col: usize) []const u8 {
        if (row == 0 and col == 0) return "╔";
        if (row == 0 and col == last_col) return "╗";
        if (row == last_row and col == 0) return "╚";
        if (row == last_row and col == last_col) return "╝";
        if (row == 0 or row == last_row) return "═";
        return "║";
    }

    fn drawStartScreen(writer: *std.Io.Writer, m: model.Model) !void {
        try writer.writeAll("\x1b[H");

        const message = "Press any key to start";
        const box_height = 3;
        const box_width = message.len + 4;
        const total_rows = m.board_height + 2;
        const total_cols = m.board_width + 2;
        const shadow_offset = 1;

        const box_top = 1 + (m.board_height -| box_height) / 2;
        const box_left = 1 + (m.board_width -| box_width) / 2;
        const last_row = total_rows - 1;
        const last_col = total_cols - 1;

        for (0..total_rows) |row| {
            for (0..total_cols) |col| {
                const is_border = row == 0 or row == total_rows - 1 or col == 0 or col == total_cols - 1;
                const in_box = row >= box_top and row < box_top + box_height and
                    col >= box_left and col < box_left + box_width;
                const in_shadow = row >= box_top + shadow_offset and row < box_top + shadow_offset + box_height and
                    col >= box_left + shadow_offset and col < box_left + shadow_offset + box_width;

                if (in_box) {
                    const box_row = row - box_top;
                    const box_col = col - box_left;
                    if (box_row == 0 or box_row == box_height - 1) {
                        try writer.writeByte(if (box_col == 0 or box_col == box_width - 1) '+' else '-');
                    } else if (box_col == 0 or box_col == box_width - 1) {
                        try writer.writeByte('|');
                    } else if (box_col == 1 or box_col == box_width - 2) {
                        try writer.writeByte(' ');
                    } else {
                        try writer.writeByte(message[box_col - 2]);
                    }
                } else if (in_shadow) {
                    try writer.writeAll("\x1b[100m \x1b[0m");
                } else if (is_border) {
                    try borderColor(writer, borderGlyph(row, col, last_row, last_col));
                } else {
                    try writer.writeByte(' ');
                }
            }
            if (row != total_rows - 1) try writer.writeByte('\n');
        }

        try writer.flush();
    }

    pub fn handleBeforeHook(writer: *std.Io.Writer, action: model.Action, original_termios: std.posix.termios) !bool {
        const before_hook: BeforeHook = switch (action) {
            .quit => .QUIT,
            .resized => .CLEAR,
            else => .NO_OP,
        };

        if (before_hook == .QUIT) {
            exitRawMode(original_termios);
            return true;
        }

        if (before_hook == .CLEAR) try writer.writeAll("\x1b[2J"); // clear stale content around the resized board
        return false;
    }
};
