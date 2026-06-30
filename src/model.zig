pub const Mode = enum {
    START,
    PLAYING,
    GAME_OVER,
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
    message_overlay_region: ?MessageRegion,
    background_sent: bool,
    background_cols: usize,
    background_rows: usize,
    dot_sprite_sent: bool,
    dot_placed: bool,
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

pub const MessageRegion = struct { top: usize, left: usize, height: usize, width: usize };

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
            .message_overlay_region = null,
            .background_sent = false,
            .background_cols = 0,
            .background_rows = 0,
            .dot_sprite_sent = false,
            .dot_placed = false,
        };
    }

    pub fn setMessageOverlayRegion(m: *Model, region: MessageRegion) void {
        m.message_overlay_region = region;
    }

    pub fn clearMessageOverlayRegion(m: *Model) void {
        m.message_overlay_region = null;
    }

    pub fn resetKittyRenderState(m: *Model) void {
        m.message_overlay_region = null;
        m.background_sent = false;
        m.background_cols = 0;
        m.background_rows = 0;
        m.dot_sprite_sent = false;
        m.dot_placed = false;
    }

    pub fn markBackgroundSent(m: *Model, cols: usize, rows: usize) void {
        m.background_sent = true;
        m.background_cols = cols;
        m.background_rows = rows;
        m.dot_sprite_sent = false;
        m.dot_placed = false;
    }

    pub fn markDotSpriteSent(m: *Model) void {
        m.dot_sprite_sent = true;
    }

    pub fn markDotPlaced(m: *Model) void {
        m.dot_placed = true;
    }

    pub fn clearDotPlaced(m: *Model) void {
        m.dot_placed = false;
    }

    fn hitsWall(position: usize, bound: usize, direction: Direction, forward: Direction, backward: Direction) bool {
        if (direction == forward) return position + 1 >= bound;
        if (direction == backward) return position == 0;
        return false;
    }

    fn advance(position: usize, direction: Direction, forward: Direction, backward: Direction) usize {
        if (direction == forward) return position + 1;
        if (direction == backward) return position - 1;
        return position;
    }

    pub fn updateModel(model: Model, action: Action) Model {
        return switch (action) {
            .tick => blk: {
                if (model.mode != .PLAYING) break :blk model;

                const ticks_since_move = model.ticks_since_move + 1;
                const ticks_per_move = @max(1, 1000 / (blocks_per_second * @as(usize, @intCast(tick_rate_ms))));
                if (ticks_since_move < ticks_per_move) break :blk .{
                    .mode = model.mode,
                    .dot_col = model.dot_col,
                    .dot_row = model.dot_row,
                    .direction = model.direction,
                    .board_width = model.board_width,
                    .board_height = model.board_height,
                    .cell_aspect_ratio = model.cell_aspect_ratio,
                    .ticks_since_move = ticks_since_move,
                    .message_overlay_region = model.message_overlay_region,
                    .background_sent = model.background_sent,
                    .background_cols = model.background_cols,
                    .background_rows = model.background_rows,
                    .dot_sprite_sent = model.dot_sprite_sent,
                    .dot_placed = model.dot_placed,
                };

                const hit_wall = hitsWall(model.dot_col, model.board_width, model.direction, .right, .left) or
                    hitsWall(model.dot_row, model.board_height, model.direction, .down, .up);

                break :blk .{
                    .mode = if (hit_wall) .GAME_OVER else model.mode,
                    .dot_col = if (hit_wall) model.dot_col else advance(model.dot_col, model.direction, .right, .left),
                    .dot_row = if (hit_wall) model.dot_row else advance(model.dot_row, model.direction, .down, .up),
                    .direction = model.direction,
                    .board_width = model.board_width,
                    .board_height = model.board_height,
                    .cell_aspect_ratio = model.cell_aspect_ratio,
                    .ticks_since_move = 0,
                    .message_overlay_region = model.message_overlay_region,
                    .background_sent = model.background_sent,
                    .background_cols = model.background_cols,
                    .background_rows = model.background_rows,
                    .dot_sprite_sent = model.dot_sprite_sent,
                    .dot_placed = model.dot_placed,
                };
            },
            .key_pressed => |direction| if (model.mode == .GAME_OVER) .{
                .mode = .PLAYING,
                .dot_col = 0,
                .dot_row = 0,
                .direction = .right,
                .board_width = model.board_width,
                .board_height = model.board_height,
                .cell_aspect_ratio = model.cell_aspect_ratio,
                .ticks_since_move = 0,
                .message_overlay_region = model.message_overlay_region,
                .background_sent = model.background_sent,
                .background_cols = model.background_cols,
                .background_rows = model.background_rows,
                .dot_sprite_sent = model.dot_sprite_sent,
                .dot_placed = model.dot_placed,
            } else .{
                .mode = if (model.mode == .START) .PLAYING else model.mode,
                .dot_col = model.dot_col,
                .dot_row = model.dot_row,
                .direction = direction orelse model.direction,
                .board_width = model.board_width,
                .board_height = model.board_height,
                .cell_aspect_ratio = model.cell_aspect_ratio,
                .ticks_since_move = model.ticks_since_move,
                .message_overlay_region = model.message_overlay_region,
                .background_sent = model.background_sent,
                .background_cols = model.background_cols,
                .background_rows = model.background_rows,
                .dot_sprite_sent = model.dot_sprite_sent,
                .dot_placed = model.dot_placed,
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
                .message_overlay_region = model.message_overlay_region,
                .background_sent = model.background_sent,
                .background_cols = model.background_cols,
                .background_rows = model.background_rows,
                .dot_sprite_sent = model.dot_sprite_sent,
                .dot_placed = model.dot_placed,
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
                .message_overlay_region = model.message_overlay_region,
                .background_sent = model.background_sent,
                .background_cols = model.background_cols,
                .background_rows = model.background_rows,
                .dot_sprite_sent = model.dot_sprite_sent,
                .dot_placed = model.dot_placed,
            },
        };
    }
};
