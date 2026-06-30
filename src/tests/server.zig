const std = @import("std");
const http = std.http;
const Server = @import("../server/server.zig").Server;
const error_handlers = @import("../server/error_handlers.zig");
const formatting = @import("../server/formatting.zig");

test "Server.init + Server.deinit" {
    const allocator = std.testing.allocator;
    var server = try Server.init(allocator);
    defer server.deinit(allocator);
    try server.route(allocator, http.Method.GET, "/", error_handlers.notFoundHandler);
}

test "Server.route" {
    const allocator = std.testing.allocator;
    var server = try Server.init(allocator);
    defer server.deinit(allocator);
    try server.route(allocator, http.Method.GET, "/", error_handlers.notFoundHandler);
    const split = try formatting.splitEndpoint(allocator, "/");
    defer allocator.free(split);
    try std.testing.expectEqual(error_handlers.notFoundHandler, try server.get.matchRoute(split));
    try server.route(allocator, http.Method.GET, "/", error_handlers.internalServerErrorHandler);
    try std.testing.expectEqual(error_handlers.internalServerErrorHandler, try server.get.matchRoute(split));
    try server.route(allocator, http.Method.POST, "/", error_handlers.notFoundHandler);
    try server.route(allocator, http.Method.PUT, "/", error_handlers.notFoundHandler);
    try server.route(allocator, http.Method.PATCH, "/", error_handlers.notFoundHandler);
    try server.route(allocator, http.Method.DELETE, "/", error_handlers.notFoundHandler);
    try server.route(allocator, http.Method.HEAD, "/", error_handlers.notFoundHandler);
    try server.route(allocator, http.Method.OPTIONS, "/", error_handlers.notFoundHandler);
    try std.testing.expectError(error.InvalidMethod, server.route(allocator, http.Method.CONNECT, "/", error_handlers.notFoundHandler));
    try std.testing.expectError(error.InvalidMethod, server.route(allocator, http.Method.TRACE, "/", error_handlers.notFoundHandler));
}
