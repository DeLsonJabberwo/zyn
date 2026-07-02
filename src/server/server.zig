const std = @import("std");
const http = std.http;
const hash_map = std.hash_map;

const Allocator = std.mem.Allocator;

const Request = @import("request.zig").Request;
const error_handlers = @import("error_handlers.zig");
const formatting = @import("formatting.zig");
const Route = @import("route.zig").Route;
const Logger = @import("../logger.zig").Logger;

pub const Handler = fn (Allocator, std.Io, *http.Server.Request) http.Server.Request.RespondOptions;

pub const Server = struct {
    allocator: Allocator,
    logger: Logger,
    methods: *hash_map.AutoHashMap(http.Method, *Route),
    get: *Route,
    post: *Route,
    put: *Route,
    patch: *Route,
    delete: *Route,
    head: *Route,
    options: *Route,
    static: *hash_map.StringHashMap([]const u8),
    running: std.atomic.Value(bool),
    listening: std.atomic.Value(bool),
    bound_port: u16,

    pub fn init(allocator: Allocator, logger: Logger) error{OutOfMemory}!Server {
        var server = Server{
            .allocator = allocator,
            .logger = logger,
            .methods = try allocator.create(hash_map.AutoHashMap(http.Method, *Route)),
            .get = try Route.init(allocator),
            .post = try Route.init(allocator),
            .put = try Route.init(allocator),
            .patch = try Route.init(allocator),
            .delete = try Route.init(allocator),
            .head = try Route.init(allocator),
            .options = try Route.init(allocator),
            .static = try allocator.create(hash_map.StringHashMap([]const u8)),
            .running = std.atomic.Value(bool).init(true),
            .listening = std.atomic.Value(bool).init(false),
            .bound_port = 0,
        };
        server.methods.* = hash_map.AutoHashMap(http.Method, *Route).init(allocator);
        server.static.* = hash_map.StringHashMap([]const u8).init(allocator);
        try server.methods.put(http.Method.GET, server.get);
        try server.methods.put(http.Method.POST, server.post);
        try server.methods.put(http.Method.PUT, server.put);
        try server.methods.put(http.Method.PATCH, server.patch);
        try server.methods.put(http.Method.DELETE, server.delete);
        try server.methods.put(http.Method.HEAD, server.head);
        try server.methods.put(http.Method.OPTIONS, server.options);
        return server;
    }

    pub fn deinit(s: *Server, allocator: Allocator) void {
        s.methods.deinit();
        s.allocator.destroy(s.methods);
        s.get.deinit(allocator);
        s.post.deinit(allocator);
        s.put.deinit(allocator);
        s.patch.deinit(allocator);
        s.delete.deinit(allocator);
        s.head.deinit(allocator);
        s.options.deinit(allocator);
        s.static.deinit();
        s.allocator.destroy(s.static);
    }

    pub fn route(s: *Server, allocator: Allocator, method: http.Method, endpoint: []const u8, handler: *const Handler) error{InvalidMethod,InvalidRouteError,OutOfMemory}!void {
        if (s.methods.get(method)) |tree| {
            const segments = formatting.splitEndpoint(allocator, endpoint) catch |err| switch (err) {
                error.InvalidEndpoint => return error.InvalidRouteError,
                error.OutOfMemory => return error.OutOfMemory,
            };
            defer allocator.free(segments);
            try tree.addRoute(allocator, segments, handler);
            s.logger.Info("Registered route {s}: {s}\n", .{@tagName(method), endpoint});
        } else {
            return error.InvalidMethod;
        }
    }

    pub fn run(s: *Server, allocator: Allocator, io: std.Io, port: u16) error{Ip4ParseError,ListenError,AcceptError,OutOfMemory}!void {
        const LISTEN_ADDR: []const u8 = "0.0.0.0";
        const addr = std.Io.net.IpAddress.parseIp4(LISTEN_ADDR, port) catch return error.Ip4ParseError;
        var listener = addr.listen(io, .{ .reuse_address = true }) catch return error.ListenError;
        defer listener.deinit(io);
        s.bound_port = listener.socket.address.getPort();
        s.listening.store(true, .release);
        s.logger.Info("Server running on port {d}.\n", .{s.bound_port});

        while (s.running.load(.acquire)) {
            var stream = listener.accept(io) catch return error.AcceptError;
            defer stream.close(io);
            const remote_addr = stream.socket.address;
            var source_buf: [64]u8 = undefined;
            const source = switch (remote_addr) {
                .ip4 => |ip4| std.fmt.bufPrint(&source_buf, "{d}.{d}.{d}.{d}", .{
                    ip4.bytes[0], ip4.bytes[1], ip4.bytes[2], ip4.bytes[3],
                }) catch "?.?.?.?",
                .ip6 => |ip6| std.fmt.bufPrint(&source_buf, "{}", .{
                    std.Io.net.Ip6Address.Unresolved{
                        .bytes = ip6.bytes,
                        .interface_name = null,
                    },
                }) catch "?:?",
            };

            var read_buffer: [4096]u8 = undefined;
            var write_buffer: [4096]u8 = undefined;
            var reader = stream.reader(io, &read_buffer);
            var writer = stream.writer(io, &write_buffer);

            var http_server = http.Server.init(&reader.interface, &writer.interface); 
            var http_req = http_server.receiveHead() catch |err| {
                s.logger.Info("error: {}\n\n", .{err});
                continue;
            };

            const start_mono = std.Io.Clock.awake.now(io);

            var respond_options = http.Server.Request.RespondOptions{};
            const target: []const u8 = http_req.head.target;
            if (s.serveStatic(allocator, io, &http_req)) {
                respond_options = http.Server.Request.RespondOptions{.status = .ok};
            } else {
                if (Request.init(allocator, &http_req, s, source)) |request| {
                    respond_options = request.handler(allocator, io, &http_req);
                    request.deinit(allocator);
                } else |err| switch (err) {
                    error.RouteNotFoundError => respond_options = error_handlers.notFoundHandler(allocator, io, &http_req),
                    error.InvalidEndpoint => respond_options = error_handlers.notFoundHandler(allocator, io, &http_req),
                    error.InvalidMethod => respond_options = error_handlers.notFoundHandler(allocator, io, &http_req),
                    error.OutOfMemory => return error.OutOfMemory,
                }
            }
            const end_mono = std.Io.Clock.awake.now(io);
            const elapsed = start_mono.durationTo(end_mono);
            const elapsed_ns = @as(u64, @intCast(elapsed.nanoseconds));

            var duration_buf: [32]u8 = undefined;
            const duration_str = if (elapsed_ns >= std.time.ns_per_ms)
                std.fmt.bufPrint(&duration_buf, "{d:.2}ms", .{@as(f64, @floatFromInt(elapsed_ns)) / @as(f64, @floatFromInt(std.time.ns_per_ms))}) catch "??ms"
            else
                std.fmt.bufPrint(&duration_buf, "{d:.3}µs", .{@as(f64, @floatFromInt(elapsed_ns)) / @as(f64, @floatFromInt(std.time.ns_per_us))}) catch "??µs";

            s.logger.Info("[HTTP] | {d:<3} | {s:<11} | {s:>15} | {s:<7} {s}\n", .{
                @intFromEnum(respond_options.status),
                duration_str,
                source,
                @tagName(http_req.head.method),
                target,
            });
        }
    }

    pub fn stop(s: *Server, io: std.Io) void {
        const port = s.bound_port;
        s.running.store(false, .release);
        const addr = std.Io.net.IpAddress.parseIp4("127.0.0.1", port) catch return;
        const stream = addr.connect(io, .{ .mode = .stream }) catch return;
        s.logger.Info("GET / HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n", .{});
        stream.close(io);
    }

    pub fn addStatic(s: *Server, io: std.Io, fs_path: []const u8, virt_path: []const u8) void {
        var dir = std.Io.Dir.cwd().openDir(io, fs_path, .{}) catch return;
        dir.close(io);
        s.static.put(virt_path, fs_path) catch return;
    }

    pub fn serveStatic(s: *Server, allocator: Allocator, io: std.Io, req: *http.Server.Request) bool {
        var endpoint = formatting.cleanEndpoint(req.head.target);

        var static_it = s.static.iterator();
        while (static_it.next()) |entry| {
            const virt_path = entry.key_ptr.*;
            const fs_path = entry.value_ptr.*;

            if (!std.mem.startsWith(u8, endpoint, virt_path)) continue;

            const remainder = endpoint[virt_path.len..];
            if (remainder.len > 0 and remainder[0] != '/') continue;

            const subpath = if (remainder.len > 0 and remainder[0] == '/') remainder[1..] else remainder;

            var depth: isize = 0;
            var it = std.mem.splitAny(u8, subpath, "/");
            while (it.next()) |component| {
                if (std.mem.eql(u8, component, "..")) {
                    depth -= 1;
                } else if (!std.mem.eql(u8, component, ".") and component.len > 0) {
                    depth += 1;
                }
                if (depth < 0) return false;
            }

            const filepath = std.fs.path.join(allocator, &[_][]const u8{fs_path, subpath}) catch return false;
            defer allocator.free(filepath);

            const content = std.Io.Dir.cwd().readFileAlloc(io, filepath, allocator, .unlimited) catch continue;
            defer allocator.free(content);

            const respond_options = http.Server.Request.RespondOptions{
                .status = .ok,
            };
            req.respond(content, respond_options) catch return false;
            return true;
        }

        return false;
    }
};
