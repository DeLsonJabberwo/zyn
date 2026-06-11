const std = @import("std");

const Allocator = std.mem.Allocator;

pub fn formatBuf(allocator: Allocator, buf: []const u8, vals: std.hash_map.StringHashMap([]const u8)) error{OutOfMemory}![]const u8 {
    var content = try std.fmt.allocPrint(allocator, "{s}", .{buf});
    var pointer: usize = 0;
    while (std.mem.find(u8, content[pointer..content.len], "{{")) |ind| {
        const beg = pointer + ind;
        pointer += ind;
        if (std.mem.find(u8, content[beg..content.len], "}}")) |end| {
            if (std.mem.find(u8, content[beg+1..end+beg], "{{")) |_| {
                pointer += 2;
                continue;
            }
            const target = std.mem.trim(u8, content[beg+2..end+beg], &std.ascii.whitespace);
            if (vals.get(target)) |new_val| {
                const before = content[0..beg];
                const after = content[beg+end+2..content.len];
                const new_content = try std.fmt.allocPrint(allocator, "{s}{s}{s}", .{before, new_val, after});
                allocator.free(content);
                content = new_content;
                pointer = 0;
            } else {
                pointer += 2;
            }
        } else {
            pointer += 2;
        }
    }
    return content;
}

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
}
