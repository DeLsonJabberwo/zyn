const std = @import("std");
const http = std.http;
const hash_map = std.hash_map;

const Allocator = std.mem.Allocator;

const Request = @import("request.zig").Request;
const error_handlers = @import("error_handlers.zig");
const formatting = @import("formatting.zig");

const Handler = fn (Allocator, std.Io, *http.Server.Request) http.Server.Request.RespondOptions;

pub const Server = struct {
    // TODO: separate by HTTP request method (GET, PUT, POST, UPDATE, DELETE, etc.)
    methods: hash_map.AutoHashMap(http.Method, *hash_map.StringHashMap(*const Handler)),
    get: hash_map.StringHashMap(*const Handler),
    post: hash_map.StringHashMap(*const Handler),
    put: hash_map.StringHashMap(*const Handler),
    patch: hash_map.StringHashMap(*const Handler),
    delete: hash_map.StringHashMap(*const Handler),
    head: hash_map.StringHashMap(*const Handler),
    options: hash_map.StringHashMap(*const Handler),
    static: hash_map.StringHashMap([]const u8),

    pub fn init(allocator: Allocator) error{OutOfMemory}!Server {
        var server = Server{
            .methods = hash_map.AutoHashMap(http.Method, *hash_map.StringHashMap(*const Handler)).init(allocator),
            .get = hash_map.StringHashMap(*const Handler).init(allocator),
            .post = hash_map.StringHashMap(*const Handler).init(allocator),
            .put = hash_map.StringHashMap(*const Handler).init(allocator),
            .patch = hash_map.StringHashMap(*const Handler).init(allocator),
            .delete = hash_map.StringHashMap(*const Handler).init(allocator),
            .head = hash_map.StringHashMap(*const Handler).init(allocator),
            .options = hash_map.StringHashMap(*const Handler).init(allocator),
            .static = hash_map.StringHashMap([]const u8).init(allocator),
        };
        try server.methods.put(http.Method.GET, &server.get);
        try server.methods.put(http.Method.POST, &server.post);
        try server.methods.put(http.Method.PUT, &server.put);
        try server.methods.put(http.Method.PATCH, &server.patch);
        try server.methods.put(http.Method.DELETE, &server.delete);
        try server.methods.put(http.Method.HEAD, &server.head);
        try server.methods.put(http.Method.OPTIONS, &server.options);
        return server;
    }

    pub fn deinit(s: *Server) void {
        s.methods.deinit();
        s.get.deinit();
        s.post.deinit();
        s.put.deinit();
        s.patch.deinit();
        s.delete.deinit();
        s.head.deinit();
        s.options.deinit();
        s.static.deinit();
    }

    pub fn route(s: *Server, method: http.Method, endpoint: []const u8, handler: *const Handler) error{InvalidMethod,OutOfMemory}!void {
        if (s.methods.get(method)) |map| {
            try map.put(endpoint, handler);
        } else {
            return error.InvalidMethod;
        }
    }

    pub fn run(s: *Server, allocator: Allocator, io: std.Io, port: u16) !void {
        const LISTEN_ADDR: []const u8 = "0.0.0.0";
        const addr = try std.Io.net.IpAddress.parseIp4(LISTEN_ADDR, port);
        var listener = try addr.listen(io, .{ .reuse_address = true });
        defer listener.deinit(io);

        while (true) {
            var stream = try listener.accept(io);
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
                std.debug.print("error: {}\n\n", .{err});
                continue;
            };

            const start_ts = std.Io.Clock.real.now(io);
            const start_mono = std.Io.Clock.awake.now(io);

            var respond_options = http.Server.Request.RespondOptions{};
            const target: []const u8 = http_req.head.target;
            if (s.serveStatic(allocator, io, &http_req)) {
                respond_options = http.Server.Request.RespondOptions{.status = .ok};
            } else {
                if (Request.init(allocator, &http_req, s, source)) |request| {
                    respond_options = request.handler(allocator, io, &http_req);
                } else |err| switch (err) {
                    error.RouteNotFoundError => respond_options = error_handlers.notFoundHandler(allocator, io, &http_req),
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

            const start_epoch_seconds = std.time.epoch.EpochSeconds{ .secs = @abs(start_ts.toSeconds()) };
            const start_epoch_day = start_epoch_seconds.getEpochDay();
            const start_day_seconds = start_epoch_seconds.getDaySeconds();
            const start_year_day = start_epoch_day.calculateYearDay();
            const start_month_day = start_year_day.calculateMonthDay();

            std.debug.print("[HTTP] {d:0>2}/{d:0>2}/{d} - {d:0>2}:{d:0>2}:{d:0>2} | {d:<3} | {s:<11} | {s:>15} | {s:<7} {s}\n", .{
                start_month_day.month.numeric(),
                start_month_day.day_index + 1,
                start_year_day.year,
                start_day_seconds.getHoursIntoDay(),
                start_day_seconds.getMinutesIntoHour(),
                start_day_seconds.getSecondsIntoMinute(),
                @intFromEnum(respond_options.status),
                duration_str,
                source,
                @tagName(http_req.head.method),
                target,
            });
        }
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
