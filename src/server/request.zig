const std = @import("std");
const http = std.http;
const hash_map = std.hash_map;

const formatting = @import("formatting.zig");
const server_eng = @import("server.zig");

const Allocator = std.mem.Allocator;
const Handler = fn (Allocator, std.Io, *http.Server.Request) http.Server.Request.RespondOptions;

pub const Request = struct {
    server: *server_eng.Server, 
    source: []const u8,
    method: http.Method,
    target: []const u8,
    endpoint: [][]const u8,
    route: []const u8,
    handler: *const Handler,
    params: hash_map.StringHashMap([]const u8),

    pub fn init(allocator: Allocator, req: *http.Server.Request, server: *server_eng.Server, source: []const u8) error{RouteNotFoundError}!*Request {
        const endpoint_entries = formatting.splitEndpoint(allocator, req.head.target);
        var request = Request{
            .server = server,
            .source = source,
            .method = req.head.method,
            .target = req.head.target,
            .endpoint = endpoint_entries,
        };
        try request.setParamsRouteHandler(allocator, server);
        return request;
    }

    fn setParamsHandler(r: *Request, allocator: Allocator, server: *server_eng.Server) error{RouteNotFoundError}!void {
        var routes_key_it = r.server.endpoints.keyIterator();
        var options = hash_map.StringHashMap([][]const u8).init(allocator);
        var max_length = 0;
        while (routes_key_it.next()) |key| {
            const endpoint = formatting.splitEndpoint(allocator, key);
            options.put(key, endpoint);
            if (endpoint.len > max_length) max_length = endpoint.len;
        }

        var l = 0;
        while (l < max_length) : (l += 1) {
            var options_it = options.iterator();
            while (options_it.next()) |entry| {
                if (entry.value_ptr[l][0] == ':') {
                    continue;
                }
                if (entry.value_ptr.*.len < (l+1) or !std.mem.eql(u8, r.endpoint[l], entry.value_ptr[l])) {
                    options.remove(entry.key_ptr.*);
                }
            }
            options_it = options.iterator();
        }
        var options_val_it = options.valueIterator();
        const remaining = options_val_it.len;
        if (remaining == 1) {
            var params = hash_map.StringHashMap([]const u8).init(allocator);
            if (options_val_it.next()) |target| {
                for (target) |item| {
                    if (item[0] == ':') {
                        params.put(item[1..], r.endpoint[l]);
                    }
                }
                r.params = params;
                r.route = options.keyIterator().next().? catch return error.RouteNotFoundError;
                r.handler = server.endpoints.get(options.keyIterator().next().? catch return error.RouteNotFoundError);
            }
        } else {
            return error.RouteNotFoundError;
        }
    }
};
