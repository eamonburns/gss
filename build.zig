const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const casl_mod = b.addModule("casl", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    const exe = b.addExecutable(.{
        .name = "casl",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "casl", .module = casl_mod },
            },
        }),
    });

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const doc_test_exe = b.addExecutable(.{
        .name = "doc_test",
        .root_module = b.createModule(.{
            .root_source_file = b.path("build/doc_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    doc_test_exe.root_module.addImport("casl", casl_mod);
    const doc_test_step = b.step("doc_test", "Run documentation tests");
    const doc_test_cmd = b.addRunArtifact(doc_test_exe);
    doc_test_step.dependOn(&doc_test_cmd.step);

    doc_test_cmd.addFileArg(b.path("README.md"));
    doc_test_cmd.addFileArg(b.path("data/style.casl"));

    const mod_tests = b.addTest(.{
        .root_module = casl_mod,
    });

    const run_mod_tests = b.addRunArtifact(mod_tests);

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);
}
