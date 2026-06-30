const std = @import("std");
const model = @import("model.zig");
const ascii_display = @import("display/ascii.zig");
const kitty_display = @import("display/kitty.zig");
const common_display = @import("display/common.zig");

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
        writer.writeAll("\x1b_Ga=d,d=A,q=2;\x1b\\\x1b[?25h\x1b[?1049l") catch {};
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

    const RenderMode = enum { kitty, ascii };

    fn detectRenderMode(writer: *std.Io.Writer, allocator: std.mem.Allocator, m: *model.Model) RenderMode {
        kitty_display.KittyDisplayUtils.ensureKittyBoardFrame(writer, allocator, m) catch {
            model.ModelUtils.resetKittyRenderState(m);
            return .ascii;
        };
        return .kitty;
    }

    pub fn drawBoard(writer: *std.Io.Writer, allocator: std.mem.Allocator, m: *model.Model) !void {
        switch (detectRenderMode(writer, allocator, m)) {
            .ascii => try ascii_display.AsciiDisplayUtils.drawAsciiFrame(writer, m.*, common_display.drawMessageOverlay),
            .kitty => try kitty_display.KittyDisplayUtils.drawKittyFrame(writer, allocator, m, common_display.drawMessageOverlay),
        }
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
