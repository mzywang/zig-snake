pub const Mode = enum {
    START,
    PLAYING,
    QUIT,
};

pub const Model = struct {
    mode: Mode,
    dot_col: usize,
    board_width: usize,
    board_height: usize,
    ticks_since_move: usize,
};

pub const tick_rate_ms: i64 = 16;
pub const blocks_per_second = 20;
pub const ticks_per_move = @max(1, 1000 / (blocks_per_second * @as(usize, @intCast(tick_rate_ms))));

pub const BoardSize = struct { width: usize, height: usize };

pub const Action = union(enum) {
    tick,
    key_pressed,
    quit,
    resized: BoardSize,
};

pub const ModelUtils = struct {
    pub fn initializeModel(initial_size: BoardSize) Model {
        return .{
            .mode = .START,
            .dot_col = 0,
            .board_width = initial_size.width,
            .board_height = initial_size.height,
            .ticks_since_move = 0,
        };
    }

    pub fn updateModel(model: Model, action: Action) Model {
        return switch (action) {
            .tick => blk: {
                if (model.mode != .PLAYING) break :blk model;

                const ticks_since_move = model.ticks_since_move + 1;
                if (ticks_since_move < ticks_per_move) break :blk .{
                    .mode = model.mode,
                    .dot_col = model.dot_col,
                    .board_width = model.board_width,
                    .board_height = model.board_height,
                    .ticks_since_move = ticks_since_move,
                };

                break :blk .{
                    .mode = model.mode,
                    .dot_col = (model.dot_col + 1) % model.board_width,
                    .board_width = model.board_width,
                    .board_height = model.board_height,
                    .ticks_since_move = 0,
                };
            },
            .key_pressed => .{
                .mode = if (model.mode == .START) .PLAYING else model.mode,
                .dot_col = model.dot_col,
                .board_width = model.board_width,
                .board_height = model.board_height,
                .ticks_since_move = model.ticks_since_move,
            },
            .quit => .{
                .mode = .QUIT,
                .dot_col = model.dot_col,
                .board_width = model.board_width,
                .board_height = model.board_height,
                .ticks_since_move = model.ticks_since_move,
            },
            .resized => |size| .{
                .mode = model.mode,
                .dot_col = model.dot_col % size.width,
                .board_width = size.width,
                .board_height = size.height,
                .ticks_since_move = model.ticks_since_move,
            },
        };
    }
};
