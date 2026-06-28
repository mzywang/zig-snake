pub const Mode = enum {
    START,
    PLAYING,
    QUIT,
};

pub const Direction = enum {
    up,
    down,
    left,
    right,
};

pub const Model = struct {
    mode: Mode,
    dot_col: usize,
    dot_row: usize,
    direction: Direction,
    board_width: usize,
    board_height: usize,
    cell_aspect_ratio: f64,
    ticks_since_move: usize,
};

pub const tick_rate_ms: i64 = 16;
pub const blocks_per_second = 20;
pub const default_cell_aspect_ratio: f64 = 2.0;

pub const BoardSize = struct {
    width: usize,
    height: usize,
    cell_aspect_ratio: f64 = default_cell_aspect_ratio,
};

pub const Action = union(enum) {
    tick,
    key_pressed: ?Direction,
    quit,
    resized: BoardSize,
};

pub const ModelUtils = struct {
    pub fn initializeModel(initial_size: BoardSize) Model {
        return .{
            .mode = .START,
            .dot_col = 0,
            .dot_row = 0,
            .direction = .right,
            .board_width = initial_size.width,
            .board_height = initial_size.height,
            .cell_aspect_ratio = initial_size.cell_aspect_ratio,
            .ticks_since_move = 0,
        };
    }

    fn advance(position: usize, bound: usize, direction: Direction, forward: Direction, backward: Direction) usize {
        if (direction == forward) return (position + 1) % bound;
        if (direction == backward) return (position + bound - 1) % bound;
        return position;
    }

    pub fn updateModel(model: Model, action: Action) Model {
        return switch (action) {
            .tick => blk: {
                if (model.mode != .PLAYING) break :blk model;

                const ticks_since_move = model.ticks_since_move + 1;
                const horizontal_ticks_per_move = @max(1, 1000 / (blocks_per_second * @as(usize, @intCast(tick_rate_ms))));
                const vertical_ticks_per_move = @max(1, @as(usize, @intFromFloat(@round(
                    @as(f64, @floatFromInt(horizontal_ticks_per_move)) * model.cell_aspect_ratio,
                ))));
                const ticks_per_move = switch (model.direction) {
                    .up, .down => vertical_ticks_per_move,
                    .left, .right => horizontal_ticks_per_move,
                };
                if (ticks_since_move < ticks_per_move) break :blk .{
                    .mode = model.mode,
                    .dot_col = model.dot_col,
                    .dot_row = model.dot_row,
                    .direction = model.direction,
                    .board_width = model.board_width,
                    .board_height = model.board_height,
                    .cell_aspect_ratio = model.cell_aspect_ratio,
                    .ticks_since_move = ticks_since_move,
                };

                break :blk .{
                    .mode = model.mode,
                    .dot_col = advance(model.dot_col, model.board_width, model.direction, .right, .left),
                    .dot_row = advance(model.dot_row, model.board_height, model.direction, .down, .up),
                    .direction = model.direction,
                    .board_width = model.board_width,
                    .board_height = model.board_height,
                    .cell_aspect_ratio = model.cell_aspect_ratio,
                    .ticks_since_move = 0,
                };
            },
            .key_pressed => |direction| .{
                .mode = if (model.mode == .START) .PLAYING else model.mode,
                .dot_col = model.dot_col,
                .dot_row = model.dot_row,
                .direction = direction orelse model.direction,
                .board_width = model.board_width,
                .board_height = model.board_height,
                .cell_aspect_ratio = model.cell_aspect_ratio,
                .ticks_since_move = model.ticks_since_move,
            },
            .quit => .{
                .mode = .QUIT,
                .dot_col = model.dot_col,
                .dot_row = model.dot_row,
                .direction = model.direction,
                .board_width = model.board_width,
                .board_height = model.board_height,
                .cell_aspect_ratio = model.cell_aspect_ratio,
                .ticks_since_move = model.ticks_since_move,
            },
            .resized => |size| .{
                .mode = model.mode,
                .dot_col = model.dot_col % size.width,
                .dot_row = model.dot_row % size.height,
                .direction = model.direction,
                .board_width = size.width,
                .board_height = size.height,
                .cell_aspect_ratio = size.cell_aspect_ratio,
                .ticks_since_move = model.ticks_since_move,
            },
        };
    }
};
