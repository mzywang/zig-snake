const std = @import("std");
const types = @import("model.zig");
const event = @import("event.zig");
const EventHandlerUtils = event.EventHandlerUtils;
const EventChannel = EventHandlerUtils.EventChannel;
const display = @import("display.zig");
const DisplayUtils = display.DisplayUtils;

pub var resize_requested: std.atomic.Value(bool) = .init(false);
const tick_rate_ms = 150;

pub fn main(init: std.process.Init) !void {
    const original_termios = try DisplayUtils.enterRawMode();
    defer DisplayUtils.exitRawMode(original_termios);

    var stdout: Stdout = .{};
    const io = init.io;
    stdout.init(io);
    const stdout_writer = stdout.writer();

    try DisplayUtils.enterAlternateScreen(stdout_writer);
    defer DisplayUtils.exitAlternateScreen(stdout_writer);

    const reigsterWindowChangeSignalHandler = EventHandlerUtils.makeWindowChangeRegistrar(&resize_requested);
    reigsterWindowChangeSignalHandler();

    var channel: EventChannel = .{};
    try EventHandlerUtils.registerEventHandler(&resize_requested, &channel, io, DisplayUtils.queryBoardSize, tick_rate_ms);

    var model = types.ModelUtils.initializeModel(DisplayUtils.queryBoardSize());
    while (true) {
        const action = channel.recv(io);
        model = types.ModelUtils.updateModel(model, action);

        if (model.mode == .QUIT) {
            DisplayUtils.exitRawMode(original_termios);
            break;
        }

        const beforeHook = if (action == .resized) .CLEAR else .NO_OP;
        try DisplayUtils.drawBoard(stdout_writer, model, beforeHook);
    }
}

const Stdout = struct {
    buffer: [1 << 16]u8 = undefined,
    file_writer: std.Io.File.Writer = undefined,

    fn init(self: *Stdout, io: std.Io) void {
        self.file_writer = .init(.stdout(), io, &self.buffer);
    }

    fn writer(self: *Stdout) *std.Io.Writer {
        return &self.file_writer.interface;
    }
};
