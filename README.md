# zyn

A lightweight HTTP server library for [Zig](https://ziglang.org/). Zero external dependencies.

## Requirements

- **Zig 0.16**

## Usage

Add `zyn` to your project with `zig fetch`:

```bash
zig fetch --save git+https://github.com/DeLsonJabberwo/zyn.git
```

Then import it in your `build.zig`:

```zig
const zyn_dep = b.dependency("zyn", .{});
exe.root_module.addImport("zyn", zyn_dep.module("zyn"));
```

And in your source code:

```zig
const zyn = @import("zyn");
```

### Example

```zig
const std = @import("std");
const zyn = @import("zyn");

fn helloHandler(allocator: std.mem.Allocator, io: std.Io, req: *std.http.Server.Request) std.http.Server.Request.RespondOptions {
    _ = allocator;
    _ = io;
    const opts: std.http.Server.Request.RespondOptions = .{ .status = .ok };
    req.respond("Hello, World!", opts) catch unreachable;
    return opts;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const io = std.Io.init();

    var server = zyn.Server.init(allocator);
    defer server.deinit();

    try server.route(std.http.Method.PUT, "/hello", &helloHandler);

    try server.run(allocator, io, 8080);
}
```

### Static Files

```zig
server.addStatic(io, "./public", "/static");
```

Files in `./public` will be served under `/static/*`.

### Templating

Simple `{{key}}` replacement is available via `formatBuf`:

```zig
var vals = std.hash_map.StringHashMap([]const u8).init(allocator);
try vals.put("name", "Zig");
const output = try zyn.formatBuf(allocator, "Hello, {{ name }}!", vals);
```

## API

| Export        | Description                          |
|---------------|--------------------------------------|
| `Server`      | HTTP server with routing and static file serving |
| `Request`     | Request wrapper (route params, metadata)         |
| `formatBuf`   | Simple `{{key}}` string replacement templating   |
| `notFoundHandler` | Handler for 404 not found errors |
| `internalServerErrorHandler` | Handler for 500 internal server errors |

## Build & Test

```bash
zig build          # Build the module
zig build test     # Run tests (native, x86_64-linux)
```

