const std = @import("std");
const http = std.http;

const Allocator = std.mem.Allocator;

pub fn notFoundHandler(_: Allocator, _: std.Io, http_req: *http.Server.Request) http.Server.Request.RespondOptions {
    const respond_options = http.Server.Request.RespondOptions{
        .status = .not_found,
    };
    http_req.respond("404 page not found", respond_options) catch unreachable;
    return respond_options;
}

pub fn internalServerErrorHandler(_: Allocator, _: std.Io, http_req: *http.Server.Request) http.Server.Request.RespondOptions {
    const resond_options = http.Server.Request.RespondOptions{
        .status = .internal_server_error,
    };
    http_req.respond("500 internal server error", resond_options) catch unreachable;
    return resond_options;
}

