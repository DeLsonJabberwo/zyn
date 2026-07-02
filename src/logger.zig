const std = @import("std");

const Allocator = std.mem.Allocator;

pub const Logger = struct {
    io: std.Io,
    writer: *std.Io.Writer,
    file: ?std.Io.File,
    choice: WriterChoice,

    pub fn init(io: std.Io, writer_choice: WriterChoice, allocator: Allocator) !Logger {
        var logger = Logger{
            .io = io,
            .writer = undefined,
            .file = null,
            .choice = writer_choice,
        };

        switch (writer_choice) {
            .stdout => {
                const fw = try allocator.create(std.Io.File.Writer);
                fw.* = std.Io.File.stdout().writer(io, &[_]u8{});
                logger.writer = &fw.interface;
            },
            .stderr => {
                const fw = try allocator.create(std.Io.File.Writer);
                fw.* = std.Io.File.stderr().writer(io, &[_]u8{});
                logger.writer = &fw.interface;
            },
            .discarding => {
                const w = try allocator.create(std.Io.Writer);
                w.* = std.Io.Writer.fixed(&[_]u8{});
                logger.writer = w;
            },
            .file => |path| {
                const f = try std.Io.Dir.cwd().createFile(io, path, .{});
                logger.file = f;
                const fw = try allocator.create(std.Io.File.Writer);
                fw.* = f.writer(io, &[_]u8{});
                logger.writer = &fw.interface;
            },
            .custom => |ptr| {
                logger.writer = ptr;
            },
        }

        return logger;
    }

    pub fn deinit(l: *Logger, allocator: Allocator) void {
        switch (l.choice) {
            .stdout, .stderr => {
                const fw: *std.Io.File.Writer = @alignCast(@fieldParentPtr("interface", l.writer));
                allocator.destroy(fw);
            },
            .discarding => allocator.destroy(l.writer),
            .file => {
                if (l.file) |f| f.close(l.io);
                const fw: *std.Io.File.Writer = @alignCast(@fieldParentPtr("interface", l.writer));
                allocator.destroy(fw);
            },
            .custom => {}, // borrowed, do not free
        }
    }

    pub fn Info(l: *Logger, comptime fmt: []const u8, args: anytype) void {
        const timestamp = std.Io.Clock.real.now(l.io);
        const epoch_seconds = std.time.epoch.EpochSeconds{ .secs = @abs(timestamp.toSeconds()) };
        const epoch_day = epoch_seconds.getEpochDay();
        const day_seconds = epoch_seconds.getDaySeconds();
        const year_day = epoch_day.calculateYearDay();
        const month_day = year_day.calculateMonthDay();

        var time_buf: [21]u8 = undefined;
        const time = std.fmt.bufPrint(&time_buf, "{d:0>4}/{d:0>2}/{d:0>2} - {d:0>2}:{d:0>2}:{d:0>2}", .{
            year_day.year,
            month_day.month.numeric(),
            month_day.day_index + 1,
            day_seconds.getHoursIntoDay(),
            day_seconds.getMinutesIntoHour(),
            day_seconds.getSecondsIntoMinute(),
        }) catch "????/??/?? - ??:??:??";

        l.writer.print("[ZYN] {s} | ", .{time}) catch return;
        l.writer.print(fmt, args) catch return;
        l.writer.writeByte('\n') catch return;
        l.writer.flush() catch return;
    }
};

const WriterChoice = union(enum) {  // tagged union = enum + payload per variant
    // Simple defaults (no extra data)
    stdout,
    stderr,
    discarding,  // e.g. for tests or silent mode

    // Defaults that need data
    file: []const u8,  // e.g. path to open

    // Bring your own — you provide the ready-to-use interface pointer
    custom: *std.Io.Writer,
};
