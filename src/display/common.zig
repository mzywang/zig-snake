const std = @import("std");
const model = @import("../model.zig");

pub const MessageRegion = model.MessageRegion;

pub fn drawMessageOverlay(writer: *std.Io.Writer, m: model.Model, message: []const u8) !MessageRegion {
    const box_height = 3;
    const box_width = message.len + 4;
    const shadow_offset = 1;
    const box_top = 1 + (m.board_height -| box_height) / 2;
    const box_left = 1 + (m.board_width -| box_width) / 2;

    const region_height = box_height + shadow_offset;
    const region_width = box_width + shadow_offset;

    for (0..region_height) |dr| {
        try writer.print("\x1b[{d};{d}H", .{ box_top + dr + 1, box_left + 1 });
        for (0..region_width) |dc| {
            const in_box = dr < box_height and dc < box_width;
            const in_shadow = !in_box and dr >= shadow_offset and dc >= shadow_offset;

            if (in_box) {
                if (dr == 0 or dr == box_height - 1) {
                    try writer.writeByte(if (dc == 0 or dc == box_width - 1) '+' else '-');
                } else if (dc == 0 or dc == box_width - 1) {
                    try writer.writeByte('|');
                } else if (dc == 1 or dc == box_width - 2) {
                    try writer.writeByte(' ');
                } else {
                    try writer.writeByte(message[dc - 2]);
                }
            } else if (in_shadow) {
                try writer.writeAll("\x1b[100m \x1b[0m");
            } else {
                try writer.writeByte(' ');
            }
        }
    }

    try writer.flush();
    return .{ .top = box_top, .left = box_left, .height = region_height, .width = region_width };
}
