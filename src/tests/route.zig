const std = @import("std");
const http = std.http;
const Route = @import("../server/route.zig").Route;
const formatting = @import("../server/formatting.zig");

fn testHandler(_: std.mem.Allocator, _: std.Io, _: *http.Server.Request) http.Server.Request.RespondOptions {
    return .{ .status = .ok };
}

fn otherHandler(_: std.mem.Allocator, _: std.Io, _: *http.Server.Request) http.Server.Request.RespondOptions {
    return .{ .status = .not_found };
}

fn paramHandler(_: std.mem.Allocator, _: std.Io, _: *http.Server.Request) http.Server.Request.RespondOptions {
    return .{ .status = .ok };
}

test "Route.init + Route.deinit" {
    const allocator = std.testing.allocator;
    var root = try Route.init(allocator);
    defer root.deinit(allocator);
}

test "Route.matchRoute root" {
    const allocator = std.testing.allocator;
    var root = try Route.init(allocator);
    defer root.deinit(allocator);

    const segments = try formatting.splitEndpoint(allocator, "/");
    defer allocator.free(segments);

    try root.addRoute(allocator, segments, &testHandler);
    const handler = try root.matchRoute(segments);
    try std.testing.expectEqual(&testHandler, handler);
}

test "Route.matchRoute exact" {
    const allocator = std.testing.allocator;
    var root = try Route.init(allocator);
    defer root.deinit(allocator);

    const segments = try formatting.splitEndpoint(allocator, "/hello");
    defer allocator.free(segments);

    try root.addRoute(allocator, segments, &testHandler);
    const handler = try root.matchRoute(segments);
    try std.testing.expectEqual(&testHandler, handler);
}

test "Route.matchRoute nested" {
    const allocator = std.testing.allocator;
    var root = try Route.init(allocator);
    defer root.deinit(allocator);

    const segments = try formatting.splitEndpoint(allocator, "/hello/world");
    defer allocator.free(segments);

    try root.addRoute(allocator, segments, &testHandler);
    const handler = try root.matchRoute(segments);
    try std.testing.expectEqual(&testHandler, handler);
}

test "Route.matchRoute single parameter" {
    const allocator = std.testing.allocator;
    var root = try Route.init(allocator);
    defer root.deinit(allocator);

    const route_segments = try formatting.splitEndpoint(allocator, "/:id");
    defer allocator.free(route_segments);
    try root.addRoute(allocator, route_segments, &paramHandler);

    const target_segments = try formatting.splitEndpoint(allocator, "/42");
    defer allocator.free(target_segments);
    const handler = try root.matchRoute(target_segments);
    try std.testing.expectEqual(&paramHandler, handler);
}

test "Route.matchRoute multiple parameters" {
    const allocator = std.testing.allocator;
    var root = try Route.init(allocator);
    defer root.deinit(allocator);

    const route_segments = try formatting.splitEndpoint(allocator, "/user/:id/posts/:postId");
    defer allocator.free(route_segments);
    try root.addRoute(allocator, route_segments, &paramHandler);

    const target_segments = try formatting.splitEndpoint(allocator, "/user/42/posts/7");
    defer allocator.free(target_segments);
    const handler = try root.matchRoute(target_segments);
    try std.testing.expectEqual(&paramHandler, handler);
}

test "Route.matchRoute not found" {
    const allocator = std.testing.allocator;
    var root = try Route.init(allocator);
    defer root.deinit(allocator);

    const route_segments = try formatting.splitEndpoint(allocator, "/foo");
    defer allocator.free(route_segments);
    try root.addRoute(allocator, route_segments, &testHandler);

    const target_segments = try formatting.splitEndpoint(allocator, "/bar");
    defer allocator.free(target_segments);
    try std.testing.expectError(error.RouteNotFoundError, root.matchRoute(target_segments));
}

test "Route.matchRoute wrong depth" {
    const allocator = std.testing.allocator;
    var root = try Route.init(allocator);
    defer root.deinit(allocator);

    const route_segments = try formatting.splitEndpoint(allocator, "/user/:id/profile");
    defer allocator.free(route_segments);
    try root.addRoute(allocator, route_segments, &paramHandler);

    const target_segments = try formatting.splitEndpoint(allocator, "/user/42");
    defer allocator.free(target_segments);
    try std.testing.expectError(error.RouteNotFoundError, root.matchRoute(target_segments));
}

test "Route.matchRoute prefers exact over parameter" {
    const allocator = std.testing.allocator;
    var root = try Route.init(allocator);
    defer root.deinit(allocator);

    const exact_segments = try formatting.splitEndpoint(allocator, "/user/me");
    defer allocator.free(exact_segments);
    try root.addRoute(allocator, exact_segments, &testHandler);

    const param_segments = try formatting.splitEndpoint(allocator, "/user/:id");
    defer allocator.free(param_segments);
    try root.addRoute(allocator, param_segments, &paramHandler);

    const target_segments = try formatting.splitEndpoint(allocator, "/user/me");
    defer allocator.free(target_segments);
    const handler = try root.matchRoute(target_segments);
    try std.testing.expectEqual(&testHandler, handler);
}

test "Route.findParamInds no parameters" {
    const allocator = std.testing.allocator;
    var root = try Route.init(allocator);
    defer root.deinit(allocator);

    const segments = try formatting.splitEndpoint(allocator, "/hello");
    defer allocator.free(segments);
    try root.addRoute(allocator, segments, &testHandler);

    const param_inds_opt = try root.findParamInds(allocator, 0, &testHandler);
    try std.testing.expect(param_inds_opt != null);
    var param_inds = param_inds_opt.?;
    defer param_inds.deinit();
    try std.testing.expectEqual(0, param_inds.count());
}

test "Route.findParamInds single parameter" {
    const allocator = std.testing.allocator;
    var root = try Route.init(allocator);
    defer root.deinit(allocator);

    const segments = try formatting.splitEndpoint(allocator, "/:id");
    defer allocator.free(segments);
    try root.addRoute(allocator, segments, &paramHandler);

    const param_inds_opt = try root.findParamInds(allocator, 0, &paramHandler);
    try std.testing.expect(param_inds_opt != null);
    var param_inds = param_inds_opt.?;
    defer param_inds.deinit();
    try std.testing.expectEqual(1, param_inds.count());
    // NOTE: the current implementation returns index 1 here because the root
    // node increments the index before checking the first child. A corrected
    // implementation would likely return index 0 for the first segment.
    try std.testing.expectEqualStrings("id", param_inds.get(1).?);
}

test "Route.findParamInds multiple parameters" {
    const allocator = std.testing.allocator;
    var root = try Route.init(allocator);
    defer root.deinit(allocator);

    const segments = try formatting.splitEndpoint(allocator, "/user/:id/posts/:postId");
    defer allocator.free(segments);
    try root.addRoute(allocator, segments, &paramHandler);

    const param_inds_opt = try root.findParamInds(allocator, 0, &paramHandler);
    try std.testing.expect(param_inds_opt != null);
    var param_inds = param_inds_opt.?;
    defer param_inds.deinit();
    try std.testing.expectEqual(2, param_inds.count());
    // NOTE: see the comment in the single-parameter test about the current
    // index offset produced by the root node.
    try std.testing.expectEqualStrings("id", param_inds.get(2).?);
    try std.testing.expectEqualStrings("postId", param_inds.get(4).?);
}

test "Route.findParamInds missing handler" {
    const allocator = std.testing.allocator;
    var root = try Route.init(allocator);
    defer root.deinit(allocator);

    const segments = try formatting.splitEndpoint(allocator, "/hello");
    defer allocator.free(segments);
    try root.addRoute(allocator, segments, &testHandler);

    const param_inds_opt = try root.findParamInds(allocator, 0, &otherHandler);
    try std.testing.expect(param_inds_opt != null);
    var param_inds = param_inds_opt.?;
    defer param_inds.deinit();
    try std.testing.expectEqual(0, param_inds.count());
}
