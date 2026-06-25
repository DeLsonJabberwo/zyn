pub const Server = @import("server/server.zig").Server;
pub const Request = @import("server/request.zig").Request;
pub const error_handlers = @import("server/error_handlers.zig");
pub const formatBuf = @import("templating/buffer.zig").formatBuf;

test {
    _ = @import("server/error_handlers.zig");
    _ = @import("server/request.zig");
    _ = @import("tests/formatting.zig");
    _ = @import("tests/buffer.zig");
    _ = @import("tests/server.zig");
}
