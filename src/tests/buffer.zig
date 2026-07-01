const std = @import("std");
const buffer = @import("../templating/buffer.zig");
const formatBuf = buffer.formatBuf;

test formatBuf {
    const allocator = std.testing.allocator;
    {
        const inputBuf = "<p>{{ msg }}<\\p>";
        const expected = "<p>Hello<\\p>";
        var vals = std.hash_map.StringHashMap([]const u8).init(allocator);
        defer vals.deinit();
        try vals.put("msg", "Hello");
        const result = try formatBuf(allocator, inputBuf, vals);
        defer allocator.free(result);
        try std.testing.expectEqualStrings(expected, result);
    }
    {
        const inputBuf = "<p>Hello<\\p>";
        const expected = "<p>Hello<\\p>";
        var vals = std.hash_map.StringHashMap([]const u8).init(allocator);
        defer vals.deinit();
        try vals.put("msg", "Hello");
        const result = try formatBuf(allocator, inputBuf, vals);
        defer allocator.free(result);
        try std.testing.expectEqualStrings(expected, result);
    }
    {
        const inputBuf = "<p>{{ name }}<\\p>";
        const expected = "<p>{{ name }}<\\p>";
        var vals = std.hash_map.StringHashMap([]const u8).init(allocator);
        defer vals.deinit();
        try vals.put("msg", "Hello");
        const result = try formatBuf(allocator, inputBuf, vals);
        defer allocator.free(result);
        try std.testing.expectEqualStrings(expected, result);
    }
    {
        const inputBuf = "<p>{{msg}}, {{ name }}<\\p>";
        const expected = "<p>Hello, {{ name }}<\\p>";
        var vals = std.hash_map.StringHashMap([]const u8).init(allocator);
        defer vals.deinit();
        try vals.put("msg", "Hello");
        const result = try formatBuf(allocator, inputBuf, vals);
        defer allocator.free(result);
        try std.testing.expectEqualStrings(expected, result);
    }
    {
        const inputBuf = "<p>{{msg}}, {{ name }}<\\p>";
        const expected = "<p>Hello, User<\\p>";
        var vals = std.hash_map.StringHashMap([]const u8).init(allocator);
        defer vals.deinit();
        try vals.put("msg", "Hello");
        try vals.put("name", "User");
        const result = try formatBuf(allocator, inputBuf, vals);
        defer allocator.free(result);
        try std.testing.expectEqualStrings(expected, result);
    }
    {
        const inputBuf = "<p>{{msg}}, {{ name }}. {{msg}}<\\p>";
        const expected = "<p>Hello, User. Hello<\\p>";
        var vals = std.hash_map.StringHashMap([]const u8).init(allocator);
        defer vals.deinit();
        try vals.put("msg", "Hello");
        try vals.put("name", "User");
        const result = try formatBuf(allocator, inputBuf, vals);
        defer allocator.free(result);
        try std.testing.expectEqualStrings(expected, result);
    }
    {
        const inputBuf = "<p>{{}}, {{ name }}. {{msg}}<\\p>";
        const expected = "<p>{{}}, User. Hello<\\p>";
        var vals = std.hash_map.StringHashMap([]const u8).init(allocator);
        defer vals.deinit();
        try vals.put("msg", "Hello");
        try vals.put("name", "User");
        const result = try formatBuf(allocator, inputBuf, vals);
        defer allocator.free(result);
        try std.testing.expectEqualStrings(expected, result);
    }
    {
        const inputBuf = "<p>{{, {{ name }}. {{msg}}<\\p>";
        const expected = "<p>{{, User. Hello<\\p>";
        var vals = std.hash_map.StringHashMap([]const u8).init(allocator);
        defer vals.deinit();
        try vals.put("msg", "Hello");
        try vals.put("name", "User");
        const result = try formatBuf(allocator, inputBuf, vals);
        defer allocator.free(result);
        try std.testing.expectEqualStrings(expected, result);
    }
    {
        const inputBuf = "<p>{{, User. Hello<\\p>";
        const expected = "<p>{{, User. Hello<\\p>";
        var vals = std.hash_map.StringHashMap([]const u8).init(allocator);
        defer vals.deinit();
        try vals.put("msg", "Hello");
        try vals.put("name", "User");
        const result = try formatBuf(allocator, inputBuf, vals);
        defer allocator.free(result);
        try std.testing.expectEqualStrings(expected, result);
    }
    // Empty buffer.
    {
        const inputBuf = "";
        const expected = "";
        var vals = std.hash_map.StringHashMap([]const u8).init(allocator);
        defer vals.deinit();
        const result = try formatBuf(allocator, inputBuf, vals);
        defer allocator.free(result);
        try std.testing.expectEqualStrings(expected, result);
    }
}
