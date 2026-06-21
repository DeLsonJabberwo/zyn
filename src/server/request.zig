const std = @import("std");
const http = std.http;
const hash_map = std.hash_map;

const formatting = @import("formatting.zig");
const Server = @import("server.zig").Server;

const Allocator = std.mem.Allocator;
const Handler = fn (Allocator, std.Io, *http.Server.Request) http.Server.Request.RespondOptions;

pub const Request = struct {
    server: *Server, 
    source: []const u8,
    method: http.Method,
    target: []const u8,
    route: []const u8,
    params: hash_map.StringHashMap([]const u8),

    pub fn init(allocator: Allocator, http_req: *http.Server.Request, server: *Server, source: []const u8) error{RouteNotFoundError,InvalidEndpoint,OutOfMemory}!*Request {
        var request = try allocator.create(Request);
        request.* = Request{
            .server = server,
            .source = source,
            .method = http_req.head.method,
            .target = http_req.head.target,
            .route = undefined,
            .params = undefined,
        };
        const target_entries = try formatting.splitEndpoint(allocator, http_req.head.target);
        try request.setParamsRoute(allocator, target_entries);
        return request;
    }

    fn setParamsRoute(r: *Request, allocator: Allocator, target_entries: [][]const u8) error{RouteNotFoundError,InvalidEndpoint,OutOfMemory}!void {
        var routes: hash_map.StringHashMap(*const Handler) = undefined;
        if (r.server.methods.get(r.method)) |map| {
            routes = map.*;
        } else {
            return error.RouteNotFoundError;
        }
        var routes_key_it = routes.keyIterator();
        var options = hash_map.StringHashMap([][]const u8).init(allocator);
        var max_length: usize = 0;
        while (routes_key_it.next()) |key| {
            const endpoint = try formatting.splitEndpoint(allocator, key.*);
            try options.put(key.*, endpoint);
            if (endpoint.len > max_length) max_length = endpoint.len;
        }

        for (0..max_length) |l| {
            var options_it = options.iterator();
            while (options_it.next()) |entry| {
                if (entry.value_ptr.*.len < (l+1) or !std.mem.eql(u8, target_entries[l], entry.value_ptr.*[l])) {
                    _ = !options.remove(entry.key_ptr.*);
                    continue;
                }
                if (entry.value_ptr.*[l].len == 0 or entry.value_ptr.*[l][0] == ':') {
                    continue;
                }
            }
            options_it = options.iterator();
        }
        var options_val_it = options.valueIterator();
        const remaining = options_val_it.len;
        if (remaining == 1) {
            var params = hash_map.StringHashMap([]const u8).init(allocator);
            if (options_val_it.next()) |target| {
                for (target.*, 0..) |item, i| {
                    if (item[0] == ':')  {
                        try params.put(item[1..], target_entries[i]);
                    }
                }
                r.params = params;
                var key_it = options.keyIterator();
                const key_ptr = key_it.next() orelse return error.RouteNotFoundError;
                r.route = key_ptr.*;
            }
        } else {
            return error.RouteNotFoundError;
        }
    }
};
