pub const Server = @import("server/server.zig").Server;
pub const Request = @import("server/request.zig").Request;
pub const error_handlers = @import("server/error_handlers.zig");
pub const formatBuf = @import("templating/buffer.zig").formatBuf;

test {
    _ = @import("server/formatting.zig");
    _ = @import("templating/buffer.zig");
    _ = @import("server/error_handlers.zig");
    _ = @import("server/request.zig");
}
