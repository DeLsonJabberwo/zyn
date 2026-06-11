# Testing Plan for `zyn`

## Current State

The `build.zig` is already wired for multi-target testing (`zig build test`) across native, `x86_64-linux`, and `aarch64-macos`. However, **no test blocks exist in any source file yet**. This plan treats the test suite as a clean start.

## Recommended Implementation Order

### Phase 1: Quick Wins (Pure Logic, No I/O)

**Start with these two files first.** They have zero `std.Io` dependencies and only require an `Allocator`.

- **`src/server/formatting.zig`** — `cleanEndpoint` and `splitEndpoint`
- **`src/templating/buffer.zig`** — `formatBuf`

These are the best files to learn Zig's built-in testing patterns on because you can verify them with just `std.testing.allocator` and string comparisons.

### Phase 2: Server Lifecycle & Routing

Test **`src/server/server.zig`** without touching the network loop.

- `Server.init()` and `Server.deinit()` — verify no memory leaks with `std.testing.allocator`
- `Server.route()` — test all valid HTTP methods and the `error.InvalidMethod` path

### Phase 3: Request Matching (Core Logic)

This is where the most critical behavior lives. `Request.init` in **`src/server/request.zig`** is tightly coupled to `std.http.Server.Request` and `Server`.

**You have two choices:**

- **Strategy A (Test as-is):** Construct a real `Server`, register routes, and try to call `Request.init` with a manually-built `std.http.Server.Request`. This can be awkward in Zig 0.16.
- **Strategy B (Recommended):** Extract the route matching logic into a pure function that takes `[][]const u8` (endpoint) and `[]const []const u8` (routes), and returns a `?MatchResult` with params. This makes the logic trivial to unit test without I/O plumbing.

### Phase 4: Error Handlers

`notFoundHandler` and `internalServerErrorHandler` call `req.respond()` (side effects). Unit testing them directly is awkward because they need a real HTTP request object.

**Strategy:** Test the "decision" (what status code they return) via integration tests, or by extracting the status-code logic into a pure helper. If you don't want integration tests, skip direct unit tests here.

### Phase 5: Integration / Static Serving

- **`serveStatic`** — The path traversal logic (`../`, `./`) is pure and can be extracted. The file-reading part needs `std.Io` and a real filesystem.
- **`run()`** — An infinite network loop. This is fundamentally an integration test.

**Strategy:** Create a dedicated test file (e.g., `src/server/server_test.zig` or inline tests) that:
1. Starts a `Server` on a test port (e.g., `18080`)
2. Uses `std.http.Client` or a raw TCP stream to send a request
3. Reads the response and asserts the status code and body

---

## Critical Test Cases Per Component

| Component | What to Test |
|-----------|-------------|
| `cleanEndpoint` | Strips `#frag` and `?query`; respects `%#` and `%?` escapes; handles empty strings; multiple consecutive fragments |
| `splitEndpoint` | `/`, `/foo`, `/foo/bar`, trailing slashes, multiple slashes, query-stripped paths |
| `formatBuf` | `{{key}}`, `{{ key }}` (with whitespace), multiple replacements, missing keys (leave untouched), empty buffer, no placeholders |
| `Server.init` / `deinit` | No memory leaks with `std.testing.allocator` |
| `Server.route` | All 7 valid methods, `error.InvalidMethod` for unsupported methods, duplicate route registration |
| `Request` matching | Exact match, `/:id`, `/user/:id/posts/:postId`, trailing segment mismatch, route not found, ambiguous routes (e.g., `/foo` and `/bar` both matching) |
| `serveStatic` | Path traversal (`../`, `..`, `./`), missing files, correct prefix matching, slash handling |
| `error_handlers` | Correct status codes (`.not_found`, `.internal_server_error`) |

---

## Testing Strategies

### 1. Always Use `std.testing.allocator`

```zig
var server = try Server.init(std.testing.allocator);
defer server.deinit();
```

This is a leak-detecting allocator. If you forget to `deinit` or free a string, the test will fail.

### 2. Use `std.testing.expectEqualStrings`

```zig
try std.testing.expectEqualStrings("expected", actual);
```

Use this for all string comparisons. It prints a diff on failure.

### 3. Assert Error Unions

```zig
try std.testing.expectError(error.InvalidMethod, server.route(.CONNECT, "/", &handler));
```

### 4. Clean Up Allocations

For functions like `splitEndpoint` that return allocated slices:

```zig
var endpoint = try splitEndpoint(allocator, "/foo/bar");
defer allocator.free(endpoint);
```

### 5. Integration Test Pattern

For the server loop, use a dedicated file or inline tests:

```zig
// Start Server on a test port in a separate thread
// Use std.http.Client to send a request
// Assert status code and body
```

Be careful to shut the server down cleanly (e.g., send a signal or use a timeout).

### 6. Multi-Target Awareness

Your `build.zig` already runs tests on native, `x86_64-linux`, and `aarch64-macos`. Don't write OS-specific tests (e.g., `/` vs `\` path separators) unless you guard them with `builtin.os.tag`.

---

## Next Steps

1. Decide whether to **refactor `request.zig` matching logic** into a pure function for easier unit testing.
2. Decide whether to write **integration tests** that start the server and make real HTTP requests, or stick to unit tests only.
3. Open `src/server/formatting.zig` and add the first `test` block.
