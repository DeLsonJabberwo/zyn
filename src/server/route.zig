const std = @import("std");

const http = std.http;
const hash_map = std.hash_map;

const Allocator = std.mem.Allocator;
const Handler = fn (Allocator, std.Io, *http.Server.Request) http.Server.Request.RespondOptions;

/// A structure representing a Route "segment"
/// Example: /home/page should be a root Route and nested sub_routes for "home" and for "page"
///
/// Invariants:
/// - `segment` is `null` only for the root node
/// - Every entry in `sub_routes` must satisfy `key == child.segment`.
/// - Parameter segments begin with ':' (e.g. ":id").
/// - `handler` is non-null only on leaf nodes produced by `addRoute`.
///
/// Routes should only be constructed through `addRoute`. Manual modification of
/// `segment` or `sub_routes` can break internal invariants.
pub const Route = struct {
    segment: ?[]const u8,
    sub_routes: hash_map.AutoHashMap([]const u8, *Route),
    handler: ?*Handler,

    pub fn init(allocator: Allocator) error{OutOfMemory}!*Route {
        const root = try allocator.create(Route);
        root.* = .{
            .segment = null,
            .sub_routes = hash_map.AutoHashMap([]const u8, *Route).init(allocator),
            .handler = null,
        };
        return root;
    }

    pub fn deinit(r: *Route, allocator: Allocator) void {
        var sub_it = r.sub_routes.valueIterator();
        while (sub_it.next()) |value| {
            value.*.deinit();
            allocator.destroy(value.*);
        }
        r.sub_routes.deinit();
        allocator.destroy(r);
    }

    /// WARNING: RECURSIVE
    /// Intended to be called on the root Route. Traverses the tree recursively. External calls to internal segments could violate tree structure intention.
    pub fn addRoute(r: *Route, allocator: Allocator, remaining_segments: [][]const u8, handler: *Handler) error{OutOfMemory,InvalidRouteError}!void {
        if (remaining_segments.len == 0) {
            return error.InvalidRouteError;
        }
        if (r.sub_routes.get(remaining_segments[0])) |sub_route| {
            return sub_route.addRoute(allocator, remaining_segments[1..], handler);
        } else {
            var new_route = try Route.init(allocator);
            new_route.segment = remaining_segments[0];
            if (remaining_segments.len == 1) {
                new_route.handler = handler;
            } else {
                try new_route.addRoute(allocator, remaining_segments[1..], handler);
            }
            try r.sub_routes.put(remaining_segments[0], new_route);
            return;
        }
    }

    /// WARNING: RECURSIVE
    /// Intended to be called on the root Route. Traverses the tree recursively. External calls to internal segments could violate tree structure intention.
    pub fn matchRoute(r: *Route, remaining_segments: [][]const u8) error{RouteNotFoundError}!?*Handler {
        if (r.segment) |segment| {
            if (std.mem.eql(u8, segment, remaining_segments[0]) or (segment.len > 0 and segment[0] == ':')) {
                if (remaining_segments.len == 1) {
                    return r.handler;
                } else if (r.sub_routes.get(remaining_segments[1])) |sub_route| {
                    return sub_route.matchRoute(remaining_segments[1..]);
                } else {
                    var sub_it = r.sub_routes.iterator();
                    while (sub_it.next()) |entry| {
                        if (entry.key_ptr.*.len > 0 and entry.key_ptr.*[0] == ':') {
                            const handler = entry.value_ptr.*.matchRoute(remaining_segments[1..]) catch continue;
                            if (handler) |h| {
                                return h;
                            }
                        }
                    }
                    return error.RouteNotFoundError;
                }
            }
            return error.RouteNotFoundError;
        } else {
            if (remaining_segments.len == 0) return error.RouteNotFoundError;
            if (r.sub_routes.get(remaining_segments[0])) |sub_route| {
                return sub_route.matchRoute(remaining_segments[0..]);
            }
            var sub_it = r.sub_routes.iterator();
            while (sub_it.next()) |entry| {
                if (entry.key_ptr.*.len > 0 and entry.key_ptr.*[0] == ':') {
                    const handler = entry.value_ptr.*.matchRoute(remaining_segments[0..]) catch continue;
                    if (handler) |h| {
                        return h;
                    }
                }
            }
            return error.RouteNotFoundError;
        }
    }

    /// WARNING: RECURSIVE
    /// Intended to be called on the root Route. Traverses the tree recursively. External calls to internal segments could violate tree structure intention.
    /// If the handler has no parameters, returns an empty map.
    /// If the handler is not present in this subtree, returns an empty map.
    /// The caller is responsible for first confirming the route exists via `matchRoute`.
    pub fn findParamInds(r: *Route, allocator: Allocator, ind: usize, handler: *Handler) error{OutOfMemory}!?hash_map.AutoHashMap(usize, []const u8) {
        var params = hash_map.AutoHashMap(usize, []const u8).init(allocator);
        if (r.segment) |segment| {
            if (segment.len > 0 and segment[0] == ':') {
                try params.put(ind, segment[1..]);
            }
        }
        if (r.handler) |h| {
            if (h == handler) {
                return params;
            }
        } else if (r.sub_routes.count() == 0) {
            params.deinit();
            params = hash_map.AutoHashMap(usize, []const u8).init(allocator);
            return params;
        }
        var sub_it = r.sub_routes.valueIterator();
        while (sub_it.next()) |value| {
            if (try value.findParamInds(allocator, ind+1, handler)) |result| {
                var result_it = result.iterator();
                while (result_it.next()) |entry| {
                    try params.put(entry.key_ptr.*, entry.value_ptr.*);
                }
                result.deinit();
                break;
            }
        }
        return params;
    }
};

