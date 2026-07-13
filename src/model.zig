const std = @import("std");

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

pub const Position = struct {
    col: usize,
    row: usize,
};

pub const max_snake_len: usize = 512;
pub const initial_snake_len: usize = 3;
pub const food_growth: usize = 3;

pub const Model = struct {
    mode: Mode,
    segments: [max_snake_len]Position,
    head_idx: usize,
    snake_len: usize,
    direction: Direction,
    board_width: usize,
    board_height: usize,
    cell_aspect_ratio: f64,
    ticks_since_move: usize,
    food: Position,
    pending_growth: usize,
    rng: std.Random.DefaultPrng,
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
    pub fn initializeModel(initial_size: BoardSize, seed: u64) Model {
        var m: Model = .{
            .mode = .START,
            .segments = undefined,
            .head_idx = 0,
            .snake_len = initial_snake_len,
            .direction = .right,
            .board_width = initial_size.width,
            .board_height = initial_size.height,
            .cell_aspect_ratio = initial_size.cell_aspect_ratio,
            .ticks_since_move = 0,
            .food = undefined,
            .pending_growth = 0,
            .rng = .init(seed),
        };
        for (0..initial_snake_len) |i| {
            m.segments[i] = .{ .col = initial_snake_len - 1 - i, .row = 0 };
        }
        m.food = spawnFood(&m);
        return m;
    }

    fn snakeOccupies(m: Model, pos: Position) bool {
        for (0..m.snake_len) |i| {
            const seg = m.segments[(m.head_idx + i) % max_snake_len];
            if (seg.col == pos.col and seg.row == pos.row) return true;
        }
        return false;
    }

    fn spawnFood(m: *Model) Position {
        const rng = m.rng.random();
        var attempts: usize = 0;
        while (attempts < 1000) : (attempts += 1) {
            const pos: Position = .{
                .col = rng.intRangeLessThan(usize, 0, m.board_width),
                .row = rng.intRangeLessThan(usize, 0, m.board_height),
            };
            if (!snakeOccupies(m.*, pos)) return pos;
        }
        return .{ .col = 0, .row = 0 };
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
                if (ticks_since_move < ticks_per_move) {
                    var m = model;
                    m.ticks_since_move = ticks_since_move;
                    break :blk m;
                }

                const head = model.segments[model.head_idx];
                const hit_wall = hitsWall(head.col, model.board_width, model.direction, .right, .left) or
                    hitsWall(head.row, model.board_height, model.direction, .down, .up);

                if (hit_wall) {
                    var m = model;
                    m.mode = .GAME_OVER;
                    break :blk m;
                }

                const new_head_idx = (model.head_idx + max_snake_len - 1) % max_snake_len;
                const new_head: Position = .{
                    .col = advance(head.col, model.direction, .right, .left),
                    .row = advance(head.row, model.direction, .down, .up),
                };
                var m = model;
                m.segments[new_head_idx] = new_head;
                m.head_idx = new_head_idx;
                m.ticks_since_move = 0;

                if (m.pending_growth > 0 and m.snake_len < max_snake_len) {
                    m.snake_len += 1;
                    m.pending_growth -= 1;
                }

                if (new_head.col == m.food.col and new_head.row == m.food.row) {
                    m.pending_growth += food_growth;
                    m.food = spawnFood(&m);
                }
                break :blk m;
            },
            .key_pressed => |direction| blk: {
                if (model.mode == .GAME_OVER) {
                    var rng = model.rng;
                    var m = initializeModel(.{ .width = model.board_width, .height = model.board_height, .cell_aspect_ratio = model.cell_aspect_ratio }, rng.next());
                    m.mode = .PLAYING;
                    break :blk m;
                }
                var m = model;
                m.mode = if (model.mode == .START) .PLAYING else model.mode;
                m.direction = direction orelse model.direction;
                break :blk m;
            },
            .quit => blk: {
                var m = model;
                m.mode = .QUIT;
                break :blk m;
            },
            .resized => |size| blk: {
                var m = model;
                m.board_width = size.width;
                m.board_height = size.height;
                m.cell_aspect_ratio = size.cell_aspect_ratio;
                const head = m.segments[m.head_idx];
                m.segments[m.head_idx] = .{ .col = head.col % size.width, .row = head.row % size.height };
                m.food = .{ .col = m.food.col % size.width, .row = m.food.row % size.height };
                break :blk m;
            },
        };
    }
};
