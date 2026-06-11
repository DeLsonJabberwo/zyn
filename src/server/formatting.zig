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

test cleanEndpoint {
    try std.testing.expectEqualStrings(cleanEndpoint("/hello?id=3"), "/hello");
    try std.testing.expectEqualStrings(cleanEndpoint("/hello#tag"), "/hello");
    try std.testing.expectEqualStrings(cleanEndpoint("/hello/world?id=3%v=4#tag"), "/hello/world");
}

test splitEndpoint {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.InvalidEndpoint, splitEndpoint(allocator, ""));
    try std.testing.expectError(error.InvalidEndpoint, splitEndpoint(allocator, "hello"));
    {
        const result = try splitEndpoint(allocator, "/");
        defer allocator.free(result);
        try std.testing.expectEqual(1, result.len);
        try std.testing.expectEqualStrings("", result[0]);
    }
    {
        const result = try splitEndpoint(allocator, "/hello");
        defer allocator.free(result);
        try std.testing.expectEqual(1, result.len);
        try std.testing.expectEqualStrings("hello", result[0]);
    }
    {
        const result = try splitEndpoint(allocator, "/hello/world");
        defer allocator.free(result);
        try std.testing.expectEqual(2, result.len);
        try std.testing.expectEqualStrings("hello", result[0]);
        try std.testing.expectEqualStrings("world", result[1]);
    }
    {
        const result = try splitEndpoint(allocator, "/hello/world#tag");
        defer allocator.free(result);
        try std.testing.expectEqual(2, result.len);
        try std.testing.expectEqualStrings("hello", result[0]);
        try std.testing.expectEqualStrings("world", result[1]);
    }
    {
        const result = try splitEndpoint(allocator, "/hello/world?id=3%var=2#tag");
        defer allocator.free(result);
        try std.testing.expectEqual(2, result.len);
        try std.testing.expectEqualStrings("hello", result[0]);
        try std.testing.expectEqualStrings("world", result[1]);
    }
}


