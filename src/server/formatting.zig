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

pub fn splitEndpoint(allocator: Allocator, target: []const u8) [][]const u8 {
    target = cleanEndpoint(target);
    var it = std.mem.splitAny(u8, target, "/");
    var len = 0;
    while (it.next()) {
        len += 1;
    }
    const endpoint = try allocator.create([len][]const u8);
    it.reset();
    var i = 0;
    while (it.next()) |str| : (i += 1) {
        endpoint[i] = str;
    }

    return endpoint;
}


