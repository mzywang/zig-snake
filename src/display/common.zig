const std = @import("std");
const model = @import("../model.zig");

pub fn drawMessageScreen(writer: *std.Io.Writer, m: model.Model, message: []const u8) !void {
    try writer.writeAll("\x1b[H");

    const box_height = 3;
    const box_width = message.len + 4;
    const cell_width = @max(1, @as(usize, @intFromFloat(@round(m.cell_aspect_ratio))));
    const board_width = m.board_width * cell_width;
    const total_rows = m.board_height + 2;
    const total_cols = board_width + 2;
    const shadow_offset = 1;

    const box_top = 1 + (m.board_height -| box_height) / 2;
    const box_left = 1 + (board_width -| box_width) / 2;
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
