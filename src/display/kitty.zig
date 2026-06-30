const std = @import("std");
const model = @import("../model.zig");
const common = @import("common.zig");

pub const KittyDisplayUtils = struct {
    pub const OverlayDrawFn = *const fn (writer: *std.Io.Writer, m: model.Model, message: []const u8) anyerror!common.MessageRegion;

    const CellMetrics = struct {
        cell_px: usize,
        oversample_y: usize,
    };

    fn computeCellMetrics(ws: std.posix.winsize) ?CellMetrics {
        if (ws.col == 0 or ws.row == 0 or ws.xpixel == 0 or ws.ypixel == 0) return null;

        const cell_px_w_f = @as(f64, @floatFromInt(ws.xpixel)) / @as(f64, @floatFromInt(ws.col));
        const cell_px_h_f = @as(f64, @floatFromInt(ws.ypixel)) / @as(f64, @floatFromInt(ws.row));
        const cell_px: usize = @max(1, @min(64, @as(usize, @intFromFloat(@floor(@min(cell_px_w_f, cell_px_h_f))))));
        const oversample_y: usize = @max(1, @as(usize, @intFromFloat(@round(cell_px_h_f / cell_px_w_f))));

        return .{ .cell_px = cell_px, .oversample_y = oversample_y };
    }

    fn backgroundImagePixelSize(total_cols: usize, total_rows: usize, metrics: CellMetrics) struct { width: usize, height: usize } {
        return .{
            .width = total_cols * metrics.cell_px,
            .height = total_rows * metrics.oversample_y * metrics.cell_px,
        };
    }

    pub fn drawKittyFrame(writer: *std.Io.Writer, allocator: std.mem.Allocator, m: *model.Model, drawMessageOverlay: OverlayDrawFn) !void {
        switch (m.mode) {
            .PLAYING => {
                if (m.message_overlay_region) |region| {
                    try blankRegion(writer, region.top, region.left, region.height, region.width);
                    model.ModelUtils.clearMessageOverlayRegion(m);
                }
                try placeDotSprite(writer, allocator, m);
            },
            .START, .GAME_OVER => {
                if (m.dot_placed) {
                    try deleteKittyImage(writer, dot_image_id);
                    model.ModelUtils.clearDotPlaced(m);
                    try writer.flush();
                }
                const region = try drawMessageOverlay(writer, m.*, if (m.mode == .START) "Press any key to start" else "Game over - press any key to restart");
                model.ModelUtils.setMessageOverlayRegion(m, region);
            },
            .QUIT => {},
        }
    }

    fn blankRegion(writer: *std.Io.Writer, top: usize, left: usize, height: usize, width: usize) !void {
        const blank_line = " " ** 256;
        for (0..height) |dr| {
            try writer.print("\x1b[{d};{d}H", .{ top + dr + 1, left + 1 });
            try writer.writeAll(blank_line[0..@min(width, blank_line.len)]);
        }
        try writer.flush();
    }

    const RgbColor = struct { r: u8, g: u8, b: u8 };
    const border_color: RgbColor = .{ .r = 200, .g = 200, .b = 200 };
    const background_color: RgbColor = .{ .r = 10, .g = 10, .b = 10 };
    const dot_color: RgbColor = .{ .r = 255, .g = 255, .b = 255 };

    const background_image_id = 1;
    const dot_image_id = 2;

    pub fn ensureKittyBoardFrame(writer: *std.Io.Writer, allocator: std.mem.Allocator, m: *model.Model) !void {
        var ws: std.posix.winsize = .{ .row = 0, .col = 0, .xpixel = 0, .ypixel = 0 };
        _ = std.c.ioctl(std.posix.STDOUT_FILENO, @intCast(std.c.T.IOCGWINSZ), &ws);
        const metrics = computeCellMetrics(ws) orelse return error.NoPixelMetrics;

        const total_cols = m.board_width + 2;
        const total_rows = m.board_height + 2;

        if (!m.background_sent or m.background_cols != total_cols or m.background_rows != total_rows) {
            if (m.background_sent) try deleteKittyImage(writer, background_image_id);
            try sendBackgroundImage(writer, allocator, total_cols, total_rows, metrics.cell_px, metrics.oversample_y);
            model.ModelUtils.markBackgroundSent(m, total_cols, total_rows);
        }

        try writer.flush();
    }

    fn placeDotSprite(writer: *std.Io.Writer, allocator: std.mem.Allocator, m: *model.Model) !void {
        var ws: std.posix.winsize = .{ .row = 0, .col = 0, .xpixel = 0, .ypixel = 0 };
        _ = std.c.ioctl(std.posix.STDOUT_FILENO, @intCast(std.c.T.IOCGWINSZ), &ws);
        const metrics = computeCellMetrics(ws) orelse return error.NoPixelMetrics;

        if (!m.dot_sprite_sent) {
            try sendDotSprite(writer, allocator, metrics.cell_px, metrics.oversample_y);
            model.ModelUtils.markDotSpriteSent(m);
        }

        if (m.dot_placed) try deleteKittyImage(writer, dot_image_id);
        try writer.print("\x1b[{d};{d}H", .{ m.dot_row + 2, m.dot_col + 2 });
        try writer.print("\x1b_Ga=p,i={d},c=1,r=1,q=2;\x1b\\", .{dot_image_id});
        model.ModelUtils.markDotPlaced(m);

        try writer.flush();
    }

    fn deleteKittyImage(writer: *std.Io.Writer, id: usize) !void {
        try writer.print("\x1b_Ga=d,d=i,i={d},q=2;\x1b\\", .{id});
    }

    fn sendBackgroundImage(writer: *std.Io.Writer, allocator: std.mem.Allocator, total_cols: usize, total_rows: usize, cell_px: usize, oversample_y: usize) !void {
        const size = backgroundImagePixelSize(total_cols, total_rows, .{ .cell_px = cell_px, .oversample_y = oversample_y });
        const width = size.width;
        const height = size.height;

        const pixels = try allocator.alloc(u8, width * height * 3);
        defer allocator.free(pixels);

        for (0..height) |py| {
            const board_row = py / (oversample_y * cell_px);
            for (0..width) |px| {
                const board_col = px / cell_px;
                const is_border = board_row == 0 or board_row == total_rows - 1 or
                    board_col == 0 or board_col == total_cols - 1;
                const color = if (is_border) border_color else background_color;
                const offset = (py * width + px) * 3;
                pixels[offset] = color.r;
                pixels[offset + 1] = color.g;
                pixels[offset + 2] = color.b;
            }
        }

        try writer.writeAll("\x1b[H");
        try transmitKittyImageData(writer, pixels, width, height, background_image_id, 'T', total_cols, total_rows, -1);
    }

    fn sendDotSprite(writer: *std.Io.Writer, allocator: std.mem.Allocator, cell_px: usize, oversample_y: usize) !void {
        const width = cell_px;
        const height = cell_px * oversample_y;

        const pixels = try allocator.alloc(u8, width * height * 3);
        defer allocator.free(pixels);

        var i: usize = 0;
        while (i < pixels.len) : (i += 3) {
            pixels[i] = dot_color.r;
            pixels[i + 1] = dot_color.g;
            pixels[i + 2] = dot_color.b;
        }

        try transmitKittyImageData(writer, pixels, width, height, dot_image_id, 't', null, null, null);
    }

    fn transmitKittyImageData(writer: *std.Io.Writer, pixels: []const u8, width: usize, height: usize, id: usize, action: u8, display_cols: ?usize, display_rows: ?usize, z: ?i32) !void {
        const raw_chunk_size = 3072;
        var offset: usize = 0;
        var first = true;
        while (offset < pixels.len) {
            const chunk_end = @min(offset + raw_chunk_size, pixels.len);
            const is_last = chunk_end == pixels.len;

            if (first) {
                try writer.print("\x1b_Ga={c},f=24,s={d},v={d},i={d},q=2,m={d}", .{
                    action, width, height, id, @as(u8, if (is_last) 0 else 1),
                });
                if (display_cols) |cols| try writer.print(",c={d}", .{cols});
                if (display_rows) |rows| try writer.print(",r={d}", .{rows});
                if (z) |zi| try writer.print(",z={d}", .{zi});
                try writer.writeByte(';');
                first = false;
            } else {
                try writer.print("\x1b_Gm={d};", .{@as(u8, if (is_last) 0 else 1)});
            }

            try writer.printBase64(pixels[offset..chunk_end]);
            try writer.writeAll("\x1b\\");
            offset = chunk_end;
        }
    }
};
