const std = @import("std");
const types = @import("model.zig");
const event = @import("event.zig");
const app = @import("app.zig");

pub var resize_requested: std.atomic.Value(bool) = .init(false);

pub fn main(init: std.process.Init) !void {
    const original_termios = try app.AppUtils.enterRawMode();
    defer app.AppUtils.exitRawMode(original_termios);

    var session: Session = .{ .model = types.ModelUtils.initializeModel(app.AppUtils.queryBoardSize()), .stdout = .{} };
    const stdout_writer = session.stdout.setup(init.io);

    try app.AppUtils.enterAlternateScreen(stdout_writer);
    defer app.AppUtils.exitAlternateScreen(stdout_writer);

    const reigsterWindowChangeSignalHandler = event.EventHandlerUtils.makeWindowChangeRegistrar(&resize_requested);
    reigsterWindowChangeSignalHandler();

    var channel: event.EventHandlerUtils.EventChannel = .{};
    try event.EventHandlerUtils.registerEventHandler(&resize_requested, &channel, init.io, app.AppUtils.queryBoardSize);

    while (true) {
        const action = channel.recv(init.io);
        session.model = types.ModelUtils.updateModel(session.model, action);

        const should_quit = try app.AppUtils.handleBeforeHook(stdout_writer, action, original_termios);
        if (should_quit) break;

        try app.AppUtils.drawBoard(stdout_writer, session.model);
    }
}

const Session = struct {
    model: types.Model,
    stdout: Stdout,
};

const Stdout = struct {
    buffer: [1 << 16]u8 = undefined,
    file_writer: std.Io.File.Writer = undefined,

    fn init(self: *Stdout, io: std.Io) void {
        self.file_writer = .init(.stdout(), io, &self.buffer);
    }

    fn writer(self: *Stdout) *std.Io.Writer {
        return &self.file_writer.interface;
    }

    fn setup(self: *Stdout, io: std.Io) *std.Io.Writer {
        self.init(io);
        return self.writer();
    }
};
