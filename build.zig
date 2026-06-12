const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const stb_c_lexer = buildStbCLexer(b, b.dependency("stb_c_lexer", .{}), target, optimize);

    const gss_mod = b.addModule("gss", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .imports = &.{
            .{ .name = "stb_c_lexer", .module = stb_c_lexer },
        },
    });

    const exe = b.addExecutable(.{
        .name = "gss",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "gss", .module = gss_mod },
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

    const mod_tests = b.addTest(.{
        .root_module = gss_mod,
    });

    const run_mod_tests = b.addRunArtifact(mod_tests);

    // const exe_tests = b.addTest(.{
    //     .root_module = exe.root_module,
    // });

    // const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    // test_step.dependOn(&run_exe_tests.step);

    // const graph = exe.root_module.getGraph();
    // for (graph.modules, graph.names) |module, name| {
    //     std.debug.print("{s}:\n", .{name});
    //     var it = module.import_table.iterator();
    //     while (it.next()) |entry| {
    //         std.debug.print("  {s}\n", .{entry.key_ptr.*});
    //     }
    // }
    // std.debug.print("done...\n", .{});
}

fn buildStbCLexer(b: *std.Build, dep: *std.Build.Dependency, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Module {
    // const mod = b.createModule(.{
    //     .target = target,
    //     .optimize = optimize,
    //     .link_libc = true,
    // });
    // mod.addCSourceFile(.{ .file = dep.path("stb_c_lexer.c") });
    // return mod;
    const translate = b.addTranslateC(.{
        .root_source_file = dep.path("stb_c_lexer.h"),
        .target = target,
        .optimize = optimize,
    });
    const stb_mod = translate.createModule();
    stb_mod.addCSourceFile(.{ .file = dep.path("stb_c_lexer.c") });
    return stb_mod;
}
