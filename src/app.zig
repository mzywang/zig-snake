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
        const cell_aspect_ratio = queryCellAspectRatio(ws);
        const cell_width = @max(1, @as(usize, @intFromFloat(@round(cell_aspect_ratio))));

        return .{
            .width = @max(min_board_width, (@as(usize, ws.col) -| 2) / cell_width),
            .height = @max(min_board_height, @as(usize, ws.row) -| 2),
            .cell_aspect_ratio = cell_aspect_ratio,
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
        const cell_width = @max(1, @as(usize, @intFromFloat(@round(m.cell_aspect_ratio))));
        try writer.writeAll("\x1b[?2026h");
        try clearInterior(writer, m, cell_width);
        try switch (m.mode) {
            .START => drawMessageScreen(writer, m, cell_width, "Press any key to start"),
            .GAME_OVER => drawMessageScreen(writer, m, cell_width, "Game over - press any key to restart"),
            else => drawPlayingBoard(writer, m, cell_width),
        };
        try writer.writeAll("\x1b[?2026l");
        try writer.flush();
    }

    fn moveTo(writer: *std.Io.Writer, row: usize, col: usize) !void {
        try writer.print("\x1b[{};{}H", .{ row + 1, col + 1 });
    }

    fn drawPlayingBoard(writer: *std.Io.Writer, m: model.Model, cell_width: usize) !void {
        try drawBorder(writer, m, cell_width);
        try drawFood(writer, m, cell_width);
        try drawSprites(writer, m, cell_width);
    }

    fn drawFood(writer: *std.Io.Writer, m: model.Model, cell_width: usize) !void {
        try moveTo(writer, m.food.row + 1, m.food.col * cell_width + 1);
        for (0..cell_width) |_| {
            try writer.writeAll("\x1b[31;1m\u{2588}\x1b[0m");
        }
    }

    fn drawBorder(writer: *std.Io.Writer, m: model.Model, cell_width: usize) !void {
        try moveTo(writer, 0, 0);
        try borderColor(writer, "╔");
        for (0..m.board_width * cell_width) |_| try borderColor(writer, "═");
        try borderColor(writer, "╗");

        for (0..m.board_height) |row| {
            try moveTo(writer, row + 1, 0);
            try borderColor(writer, "║");
            try moveTo(writer, row + 1, m.board_width * cell_width + 1);
            try borderColor(writer, "║");
        }

        try moveTo(writer, m.board_height + 1, 0);
        try borderColor(writer, "╚");
        for (0..m.board_width * cell_width) |_| try borderColor(writer, "═");
        try borderColor(writer, "╝");
    }

    fn clearInterior(writer: *std.Io.Writer, m: model.Model, cell_width: usize) !void {
        for (0..m.board_height) |row| {
            try moveTo(writer, row + 1, 1);
            for (0..m.board_width * cell_width) |_| try writer.writeByte(' ');
        }
    }

    fn drawSprites(writer: *std.Io.Writer, m: model.Model, cell_width: usize) !void {
        for (0..m.snake_len) |i| {
            const seg = m.segments[(m.head_idx + i) % model.max_snake_len];
            const color = if (i == 0) "\x1b[32;1m" else "\x1b[32m";
            try moveTo(writer, seg.row + 1, seg.col * cell_width + 1);
            for (0..cell_width) |_| {
                try writer.writeAll(color);
                try writer.writeAll("\u{2588}\x1b[0m");
            }
        }
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

    fn drawMessageScreen(writer: *std.Io.Writer, m: model.Model, cell_width: usize, message: []const u8) !void {
        const box_height = 3;
        const box_width = message.len + 4;
        const board_width = m.board_width * cell_width;
        const shadow_offset = 1;
        const box_top = 1 + (m.board_height -| box_height) / 2;
        const box_left = 1 + (board_width -| box_width) / 2;

        try drawMessageBorder(writer, m, board_width);
        try drawMessageShadow(writer, box_top, box_left, box_height, box_width, shadow_offset);
        try drawMessageBox(writer, box_top, box_left, box_height, box_width);
        try drawMessageText(writer, message, box_top, box_left);
    }

    fn drawMessageBorder(writer: *std.Io.Writer, m: model.Model, board_width: usize) !void {
        const total_rows = m.board_height + 2;
        const total_cols = board_width + 2;
        const last_row = total_rows - 1;
        const last_col = total_cols - 1;

        for (0..total_rows) |row| {
            for (0..total_cols) |col| {
                const is_border = row == 0 or row == last_row or col == 0 or col == last_col;
                if (is_border) {
                    try moveTo(writer, row, col);
                    try borderColor(writer, borderGlyph(row, col, last_row, last_col));
                }
            }
        }
    }

    fn drawMessageShadow(writer: *std.Io.Writer, box_top: usize, box_left: usize, box_height: usize, box_width: usize, shadow_offset: usize) !void {
        for (0..box_height) |row| {
            try moveTo(writer, box_top + shadow_offset + row, box_left + shadow_offset);
            for (0..box_width) |_| try writer.writeAll("\x1b[100m \x1b[0m");
        }
    }

    fn drawMessageBox(writer: *std.Io.Writer, box_top: usize, box_left: usize, box_height: usize, box_width: usize) !void {
        for (0..box_height) |row| {
            try moveTo(writer, box_top + row, box_left);
            for (0..box_width) |col| {
                const is_top_or_bottom = row == 0 or row == box_height - 1;
                const is_left_or_right = col == 0 or col == box_width - 1;
                if (is_top_or_bottom) {
                    try writer.writeByte(if (is_left_or_right) '+' else '-');
                } else {
                    try writer.writeByte(if (is_left_or_right) '|' else ' ');
                }
            }
        }
    }

    fn drawMessageText(writer: *std.Io.Writer, message: []const u8, box_top: usize, box_left: usize) !void {
        try moveTo(writer, box_top + 1, box_left + 2);
        try writer.writeAll(message);
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
