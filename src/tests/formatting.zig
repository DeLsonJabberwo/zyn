const std = @import("std");
const formatting = @import("../server/formatting.zig");
const cleanEndpoint = formatting.cleanEndpoint;
const splitEndpoint = formatting.splitEndpoint;

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
