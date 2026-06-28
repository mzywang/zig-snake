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
};

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
        };
    }

    pub fn updateModel(model: Model, action: Action) Model {
        return switch (action) {
            .tick => .{
                .mode = model.mode,
                .dot_col = if (model.mode == .PLAYING) (model.dot_col + 1) % model.board_width else model.dot_col,
                .board_width = model.board_width,
                .board_height = model.board_height,
            },
            .key_pressed => .{
                .mode = if (model.mode == .START) .PLAYING else model.mode,
                .dot_col = model.dot_col,
                .board_width = model.board_width,
                .board_height = model.board_height,
            },
            .quit => .{
                .mode = .QUIT,
                .dot_col = model.dot_col,
                .board_width = model.board_width,
                .board_height = model.board_height,
            },
            .resized => |size| .{
                .mode = model.mode,
                .dot_col = model.dot_col % size.width,
                .board_width = size.width,
                .board_height = size.height,
            },
        };
    }
};
