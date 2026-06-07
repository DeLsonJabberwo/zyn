const std = @import("std");

const test_targets = [_]std.Target.Query{
    .{}, // native
    .{
        .cpu_arch = .x86_64,
        .os_tag = .linux,
    },
    .{
        .cpu_arch = .aarch64,
        .os_tag = .macos,
    },
};

pub fn build(b: *std.Build) void {
    // Expose zyn as a module so other Zig projects can import it.
    // They will write:  const zyn = @import("zyn");
    _ = b.addModule("zyn", .{
        .root_source_file = b.path("src/zyn.zig"),
    });

    // Tests: `zig build test`
    const test_step = b.step("test", "Run unit tests");

    for (test_targets) |target| {
        const unit_tests = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/zyn.zig"),
                .target = b.resolveTargetQuery(target),
            }),
        });

        const run_unit_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&run_unit_tests.step);
    }
}
