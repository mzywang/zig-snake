const std = @import("std");
const types = @import("model.zig");
const event = @import("event.zig");
const app = @import("app.zig");

pub var resize_requested: std.atomic.Value(bool) = .init(false);

pub fn main(init: std.process.Init) !void {
    const original_termios = try app.AppUtils.enterRawMode();
    defer app.AppUtils.exitRawMode(original_termios);

    var app_session: app.AppUtils.Session = .{ .model = types.ModelUtils.initializeModel(app.AppUtils.queryBoardSize()), .stdout = .{} };
    const stdout_writer = app_session.stdout.setup(init.io);

    try app.AppUtils.enterAlternateScreen(stdout_writer);
    defer app.AppUtils.exitAlternateScreen(stdout_writer);

    const reigsterWindowChangeSignalHandler = event.EventHandlerUtils.makeWindowChangeRegistrar(&resize_requested);
    reigsterWindowChangeSignalHandler();

    var channel: event.EventHandlerUtils.EventChannel = .{};
    try event.EventHandlerUtils.registerEventHandler(&resize_requested, &channel, init.io, app.AppUtils.queryBoardSize);

    while (true) {
        const action = channel.recv(init.io);
        app_session.model = types.ModelUtils.updateModel(app_session.model, action);

        const should_quit = try app.AppUtils.handleBeforeHook(stdout_writer, action, original_termios);
        if (should_quit) break;

        try app.AppUtils.drawBoard(stdout_writer, app_session.model);
    }
}
