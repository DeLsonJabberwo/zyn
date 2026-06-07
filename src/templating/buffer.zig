const std = @import("std");

const Allocator = std.mem.Allocator;

pub fn formatBuf(allocator: Allocator, buf: []const u8, vals: std.hash_map.StringHashMap([]const u8)) error{OutOfMemory}![]const u8 {
    var content = try std.fmt.allocPrint(allocator, "{s}", .{buf});
    var pointer: usize = 0;
    while (std.mem.find(u8, content[pointer..content.len], "{{")) |ind| {
        const beg = pointer + ind;
        pointer += ind;
        if (std.mem.find(u8, content[beg..content.len], "}}")) |end| {
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
        }
    }
    return content;
}
