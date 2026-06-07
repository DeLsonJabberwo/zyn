# zyn — Agent Notes

## Build & Test

- `zig build test` — runs tests across **3 targets** (native, x86_64-linux, aarch64-macos)
- `zig build` — standard build
- No external dependencies; all code is self-contained

## Project Structure

- `src/zyn.zig` — **module entry point**; exports `Server`, `Request`, `formatBuf`
- `src/server/` — HTTP server core (`server.zig`, `request.zig`, `error_handlers.zig`, `formatting.zig`)
- `src/templating/buffer.zig` — simple `{{key}}` string-replacement templating

## Module Usage

`build.zig` exposes `zyn` as an importable module. Other projects consume it via:
```zig
const zyn = @import("zyn");
```

## Critical API Note

This codebase targets **Zig 0.16** and uses `std.Io` (e.g., `std.Io.net.IpAddress`, `std.Io.Clock`, `std.Io.Dir.cwd()`). Do not assume `std.fs` or `std.net` APIs will work here.

