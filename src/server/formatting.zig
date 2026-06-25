const std = @import("std");

const Allocator = std.mem.Allocator;

pub fn cleanEndpoint(target: []const u8) []const u8 {
    var endpoint = target;
    while (std.mem.findLast(u8, endpoint, "#")) |index| {
        if (endpoint[index - 1] != '%') {
            endpoint = endpoint[0..index];
        }
    }
    while (std.mem.findLast(u8, endpoint, "?")) |index| {
        if (endpoint[index - 1] != '%') {
            endpoint = endpoint[0..index];
        }
    }
    return endpoint;
}

/// Calls formatting.cleanEndpoint(target)
pub fn splitEndpoint(allocator: Allocator, target: []const u8) error{InvalidEndpoint,OutOfMemory}![][]const u8 {
    const clean = cleanEndpoint(target);
    if (clean.len == 0 or clean[0] != '/') {
        return error.InvalidEndpoint;
    }
    var it = std.mem.splitAny(u8, clean, "/");
    var len: usize = 0;
    while (it.next()) |_| {
        len += 1;
    }
    const endpoint = try allocator.alloc([]const u8, len-1);
    it.reset();
    var i: usize = 0;
    _ = it.next();
    while (it.next()) |str| : (i += 1) {
        endpoint[i] = str;
    }

    return endpoint;
}


