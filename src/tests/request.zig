const std = @import("std");
const http = std.http;
const Server = @import("../server/server.zig").Server;
const Request = @import("../server/request.zig").Request;

// NOTE: The parameter-extraction tests below expose a bug in the current
// `Route.findParamInds` implementation: it returns indices with a +1 offset
// relative to the target segment slice, so `Request.matchParams` reads out of
// bounds. They are left uncommented so the failure is visible.

fn okHandler(_: std.mem.Allocator, _: std.Io, _: *http.Server.Request) http.Server.Request.RespondOptions {
    return .{ .status = .ok };
}

fn otherHandler(_: std.mem.Allocator, _: std.Io, _: *http.Server.Request) http.Server.Request.RespondOptions {
    return .{ .status = .not_found };
}

fn makeRequest(
    allocator: std.mem.Allocator,
    server: *Server,
    source: []const u8,
    request_bytes: []const u8,
) !*Request {
    var out_buf: [4096]u8 = undefined;
    var io_reader = std.Io.Reader.fixed(request_bytes);
    var io_writer = std.Io.Writer.fixed(&out_buf);

    var http_server = std.http.Server.init(&io_reader, &io_writer);
    var http_req = try http_server.receiveHead();

    return try Request.init(allocator, &http_req, server, source);
}

test "Request.init + Request.deinit" {
    const allocator = std.testing.allocator;
    var server = try Server.init(allocator);
    defer server.deinit(allocator);

    try server.route(allocator, .GET, "/", &okHandler);

    const request_bytes = "GET / HTTP/1.1\r\n\r\n";
    const req = try makeRequest(allocator, &server, "127.0.0.1", request_bytes);
    defer req.deinit(allocator);
}

test "Request.init matches root route" {
    const allocator = std.testing.allocator;
    var server = try Server.init(allocator);
    defer server.deinit(allocator);

    try server.route(allocator, .GET, "/", &okHandler);

    const request_bytes = "GET / HTTP/1.1\r\n\r\n";
    const req = try makeRequest(allocator, &server, "127.0.0.1", request_bytes);
    defer req.deinit(allocator);

    try std.testing.expectEqualStrings("", req.route);
    try std.testing.expectEqual(&okHandler, req.handler);
    try std.testing.expectEqual(0, req.params.count());
}

test "Request.init matches exact route" {
    const allocator = std.testing.allocator;
    var server = try Server.init(allocator);
    defer server.deinit(allocator);

    try server.route(allocator, .GET, "/hello", &okHandler);

    const request_bytes = "GET /hello HTTP/1.1\r\n\r\n";
    const req = try makeRequest(allocator, &server, "127.0.0.1", request_bytes);
    defer req.deinit(allocator);

    try std.testing.expectEqualStrings("hello", req.route);
    try std.testing.expectEqual(&okHandler, req.handler);
    try std.testing.expectEqual(0, req.params.count());
}

test "Request.init matches nested exact route" {
    const allocator = std.testing.allocator;
    var server = try Server.init(allocator);
    defer server.deinit(allocator);

    try server.route(allocator, .GET, "/hello/world", &okHandler);

    const request_bytes = "GET /hello/world HTTP/1.1\r\n\r\n";
    const req = try makeRequest(allocator, &server, "127.0.0.1", request_bytes);
    defer req.deinit(allocator);

    try std.testing.expectEqualStrings("hello/world", req.route);
    try std.testing.expectEqual(&okHandler, req.handler);
    try std.testing.expectEqual(0, req.params.count());
}

test "Request.init duplicate route uses latest handler" {
    const allocator = std.testing.allocator;
    var server = try Server.init(allocator);
    defer server.deinit(allocator);

    try server.route(allocator, .GET, "/hello", &okHandler);
    try server.route(allocator, .GET, "/hello", &otherHandler);

    const request_bytes = "GET /hello HTTP/1.1\r\n\r\n";
    const req = try makeRequest(allocator, &server, "127.0.0.1", request_bytes);
    defer req.deinit(allocator);

    try std.testing.expectEqual(&otherHandler, req.handler);
}

test "Request.init route not found" {
    const allocator = std.testing.allocator;
    var server = try Server.init(allocator);
    defer server.deinit(allocator);

    try server.route(allocator, .GET, "/foo", &okHandler);

    const request_bytes = "GET /bar HTTP/1.1\r\n\r\n";
    try std.testing.expectError(error.RouteNotFoundError, makeRequest(allocator, &server, "127.0.0.1", request_bytes));
}

test "Request.init trailing segment mismatch" {
    const allocator = std.testing.allocator;
    var server = try Server.init(allocator);
    defer server.deinit(allocator);

    try server.route(allocator, .GET, "/user/:id/profile", &okHandler);

    const request_bytes = "GET /user/42 HTTP/1.1\r\n\r\n";
    try std.testing.expectError(error.RouteNotFoundError, makeRequest(allocator, &server, "127.0.0.1", request_bytes));
}

test "Request.init invalid endpoint" {
    const allocator = std.testing.allocator;
    var server = try Server.init(allocator);
    defer server.deinit(allocator);

    try server.route(allocator, .GET, "/hello", &okHandler);

    const request_bytes = "GET hello HTTP/1.1\r\n\r\n";
    try std.testing.expectError(error.InvalidEndpoint, makeRequest(allocator, &server, "127.0.0.1", request_bytes));
}

test "Request.init invalid method" {
    const allocator = std.testing.allocator;
    var server = try Server.init(allocator);
    defer server.deinit(allocator);

    try server.route(allocator, .GET, "/hello", &okHandler);

    const request_bytes = "CONNECT /hello HTTP/1.1\r\n\r\n";
    try std.testing.expectError(error.InvalidMethod, makeRequest(allocator, &server, "127.0.0.1", request_bytes));
}

test "Request.init prefers exact route over parameter" {
    const allocator = std.testing.allocator;
    var server = try Server.init(allocator);
    defer server.deinit(allocator);

    try server.route(allocator, .GET, "/user/me", &okHandler);
    try server.route(allocator, .GET, "/user/:id", &otherHandler);

    const request_bytes = "GET /user/me HTTP/1.1\r\n\r\n";
    const req = try makeRequest(allocator, &server, "127.0.0.1", request_bytes);
    defer req.deinit(allocator);

    try std.testing.expectEqual(&okHandler, req.handler);
    try std.testing.expectEqual(0, req.params.count());
}

test "Request.init single parameter" {
    const allocator = std.testing.allocator;
    var server = try Server.init(allocator);
    defer server.deinit(allocator);

    try server.route(allocator, .GET, "/:id", &okHandler);

    const request_bytes = "GET /42 HTTP/1.1\r\n\r\n";
    const req = try makeRequest(allocator, &server, "127.0.0.1", request_bytes);
    defer req.deinit(allocator);

    try std.testing.expectEqual(&okHandler, req.handler);
    try std.testing.expectEqualStrings("42", req.params.get("id").?);
}

test "Request.init multiple parameters" {
    const allocator = std.testing.allocator;
    var server = try Server.init(allocator);
    defer server.deinit(allocator);

    try server.route(allocator, .GET, "/user/:id/posts/:postId", &okHandler);

    const request_bytes = "GET /user/42/posts/7 HTTP/1.1\r\n\r\n";
    const req = try makeRequest(allocator, &server, "127.0.0.1", request_bytes);
    defer req.deinit(allocator);

    try std.testing.expectEqualStrings("42", req.params.get("id").?);
    try std.testing.expectEqualStrings("7", req.params.get("postId").?);
}
