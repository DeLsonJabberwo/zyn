const std = @import("std");
const http = std.http;
const Server = @import("../server/server.zig").Server;
const Logger = @import("../logger.zig").Logger;

fn pingHandler(_: std.mem.Allocator, _: std.Io, req: *http.Server.Request) http.Server.Request.RespondOptions {
    req.respond("pong", .{ .status = .ok }) catch unreachable;
    return .{ .status = .ok };
}

fn runServer(server: *Server, allocator: std.mem.Allocator, io: std.Io, port: u16, err_out: *?anyerror) void {
    server.run(allocator, io, port) catch |err| {
        err_out.* = err;
    };
}

fn waitForServer(server: *Server) !void {
    var i: usize = 0;
    while (!server.listening.load(.acquire)) {
        if (i > 10000) return error.ServerListenTimeout;
        try std.Thread.yield();
        i += 1;
    }
}

test "run serves routes and static files" {
    const allocator = std.testing.allocator;
    var logger = try Logger.init(std.testing.io, .discarding, allocator);
    defer logger.deinit(allocator);
    var server = try Server.init(allocator, logger);
    defer server.deinit(allocator);

    try server.route(allocator, .GET, "/ping", &pingHandler);

    // Set up a temp static directory under /tmp so it does not pollute the
    // project root if cleanup fails.
    const fs_path = "/tmp/zyn_test_static";
    std.Io.Dir.cwd().deleteTree(std.testing.io, fs_path) catch {};
    try std.Io.Dir.cwd().createDirPath(std.testing.io, fs_path);
    defer std.Io.Dir.cwd().deleteTree(std.testing.io, fs_path) catch {};

    const file_path = try std.fs.path.join(allocator, &[_][]const u8{ fs_path, "hello.txt" });
    defer allocator.free(file_path);
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{
        .sub_path = file_path,
        .data = "hello static",
    });

    server.addStatic(std.testing.io, fs_path, "/static");

    var server_err: ?anyerror = null;
    const port: u16 = 0;
    const thread = try std.Thread.spawn(.{}, runServer, .{
        &server, allocator, std.testing.io, port, &server_err,
    });
    errdefer {
        server.stop(std.testing.io);
        thread.join();
    }

    try waitForServer(&server);
    const actual_port = server.bound_port;

    var client: std.http.Client = .{
        .allocator = allocator,
        .io = std.testing.io,
    };
    defer client.deinit();

    var url_buf: [128]u8 = undefined;
    var body_buf: [4096]u8 = undefined;

    // Registered route returns 200.
    {
        var writer = std.Io.Writer.fixed(&body_buf);
        const url = try std.fmt.bufPrint(&url_buf, "http://127.0.0.1:{d}/ping", .{actual_port});
        const result = try client.fetch(.{ .location = .{ .url = url }, .response_writer = &writer, .keep_alive = false });
        try std.testing.expectEqual(.ok, result.status);
        try std.testing.expectEqualStrings("pong", writer.buffered());
    }

    // Static file returns 200.
    {
        var writer = std.Io.Writer.fixed(&body_buf);
        const url = try std.fmt.bufPrint(&url_buf, "http://127.0.0.1:{d}/static/hello.txt", .{actual_port});
        const result = try client.fetch(.{ .location = .{ .url = url }, .response_writer = &writer, .keep_alive = false });
        try std.testing.expectEqual(.ok, result.status);
        try std.testing.expectEqualStrings("hello static", writer.buffered());
    }

    // Missing static file falls through to routing and returns 404.
    {
        var writer = std.Io.Writer.fixed(&body_buf);
        const url = try std.fmt.bufPrint(&url_buf, "http://127.0.0.1:{d}/static/missing.txt", .{actual_port});
        const result = try client.fetch(.{ .location = .{ .url = url }, .response_writer = &writer, .keep_alive = false });
        try std.testing.expectEqual(.not_found, result.status);
    }

    // Path traversal is rejected by serveStatic and returns 404.
    {
        var writer = std.Io.Writer.fixed(&body_buf);
        const url = try std.fmt.bufPrint(&url_buf, "http://127.0.0.1:{d}/static/../secret.txt", .{actual_port});
        const result = try client.fetch(.{ .location = .{ .url = url }, .response_writer = &writer, .keep_alive = false });
        try std.testing.expectEqual(.not_found, result.status);
    }

    // A single ".." segment also escapes the static root.
    {
        var writer = std.Io.Writer.fixed(&body_buf);
        const url = try std.fmt.bufPrint(&url_buf, "http://127.0.0.1:{d}/static/..", .{actual_port});
        const result = try client.fetch(.{ .location = .{ .url = url }, .response_writer = &writer, .keep_alive = false });
        try std.testing.expectEqual(.not_found, result.status);
    }

    // Multiple ".." segments escaping the static root.
    {
        var writer = std.Io.Writer.fixed(&body_buf);
        const url = try std.fmt.bufPrint(&url_buf, "http://127.0.0.1:{d}/static/foo/../../secret.txt", .{actual_port});
        const result = try client.fetch(.{ .location = .{ .url = url }, .response_writer = &writer, .keep_alive = false });
        try std.testing.expectEqual(.not_found, result.status);
    }

    // "." is a no-op and the file is served.
    {
        var writer = std.Io.Writer.fixed(&body_buf);
        const url = try std.fmt.bufPrint(&url_buf, "http://127.0.0.1:{d}/static/./hello.txt", .{actual_port});
        const result = try client.fetch(.{ .location = .{ .url = url }, .response_writer = &writer, .keep_alive = false });
        try std.testing.expectEqual(.ok, result.status);
        try std.testing.expectEqualStrings("hello static", writer.buffered());
    }

    // Double slashes collapse and the file is served.
    {
        var writer = std.Io.Writer.fixed(&body_buf);
        const url = try std.fmt.bufPrint(&url_buf, "http://127.0.0.1:{d}/static//hello.txt", .{actual_port});
        const result = try client.fetch(.{ .location = .{ .url = url }, .response_writer = &writer, .keep_alive = false });
        try std.testing.expectEqual(.ok, result.status);
        try std.testing.expectEqualStrings("hello static", writer.buffered());
    }

    // Wrong prefix falls through to routing and returns 404.
    {
        var writer = std.Io.Writer.fixed(&body_buf);
        const url = try std.fmt.bufPrint(&url_buf, "http://127.0.0.1:{d}/other/hello.txt", .{actual_port});
        const result = try client.fetch(.{ .location = .{ .url = url }, .response_writer = &writer, .keep_alive = false });
        try std.testing.expectEqual(.not_found, result.status);
    }

    // Request to the prefix without a file returns 404.
    {
        var writer = std.Io.Writer.fixed(&body_buf);
        const url = try std.fmt.bufPrint(&url_buf, "http://127.0.0.1:{d}/static", .{actual_port});
        const result = try client.fetch(.{ .location = .{ .url = url }, .response_writer = &writer, .keep_alive = false });
        try std.testing.expectEqual(.not_found, result.status);
    }

    // Same for the prefix with a trailing slash.
    {
        var writer = std.Io.Writer.fixed(&body_buf);
        const url = try std.fmt.bufPrint(&url_buf, "http://127.0.0.1:{d}/static/", .{actual_port});
        const result = try client.fetch(.{ .location = .{ .url = url }, .response_writer = &writer, .keep_alive = false });
        try std.testing.expectEqual(.not_found, result.status);
    }

    // Trailing slash on a file returns 404.
    {
        var writer = std.Io.Writer.fixed(&body_buf);
        const url = try std.fmt.bufPrint(&url_buf, "http://127.0.0.1:{d}/static/hello.txt/", .{actual_port});
        const result = try client.fetch(.{ .location = .{ .url = url }, .response_writer = &writer, .keep_alive = false });
        try std.testing.expectEqual(.not_found, result.status);
    }

    server.stop(std.testing.io);
    thread.join();
    if (server_err) |err| return err;
}
