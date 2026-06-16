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

    { // Definitions
        //  "0|[1-9][0-9]*"                        CLEX_intlit
        stb_mod.addCMacro("STB_C_LEX_C_DECIMAL_INTS", "Y");
        //  "0x[0-9a-fA-F]+"                       CLEX_intlit
        stb_mod.addCMacro("STB_C_LEX_C_HEX_INTS", "Y");
        //  "[0-7]+"                               CLEX_intlit
        stb_mod.addCMacro("STB_C_LEX_C_OCTAL_INTS", "Y");
        //  "[0-9]*(.[0-9]*([eE][-+]?[0-9]+)?)     CLEX_floatlit
        stb_mod.addCMacro("STB_C_LEX_C_DECIMAL_FLOATS", "Y");
        //  "0x{hex}+(.{hex}*)?[pP][-+]?{hex}+     CLEX_floatlit
        stb_mod.addCMacro("STB_C_LEX_C99_HEX_FLOATS", "N");
        //  "[_a-zA-Z][_a-zA-Z0-9]*"               CLEX_id
        stb_mod.addCMacro("STB_C_LEX_C_IDENTIFIERS", "Y");
        //  double-quote-delimited strings with escapes  CLEX_dqstring
        stb_mod.addCMacro("STB_C_LEX_C_DQ_STRINGS", "Y");
        //  single-quote-delimited strings with escapes  CLEX_ssstring
        stb_mod.addCMacro("STB_C_LEX_C_SQ_STRINGS", "N");
        //  single-quote-delimited character with escape CLEX_charlits
        stb_mod.addCMacro("STB_C_LEX_C_CHARS", "Y");
        //  "/* comment */"
        stb_mod.addCMacro("STB_C_LEX_C_COMMENTS", "Y");
        //  "// comment to end of line\n"
        stb_mod.addCMacro("STB_C_LEX_CPP_COMMENTS", "Y");
        //  "==" CLEX_eq  "!=" CLEX_noteq   "<=" CLEX_lesseq  ">=" CLEX_greatereq
        stb_mod.addCMacro("STB_C_LEX_C_COMPARISONS", "Y");
        //  "&&"  CLEX_andand   "||"  CLEX_oror
        stb_mod.addCMacro("STB_C_LEX_C_LOGICAL", "Y");
        //  "<<"  CLEX_shl      ">>"  CLEX_shr
        stb_mod.addCMacro("STB_C_LEX_C_SHIFTS", "Y");
        //  "++"  CLEX_plusplus "--"  CLEX_minusminus
        stb_mod.addCMacro("STB_C_LEX_C_INCREMENTS", "Y");
        //  "->"  CLEX_arrow
        stb_mod.addCMacro("STB_C_LEX_C_ARROW", "Y");
        //  "=>"  CLEX_eqarrow
        stb_mod.addCMacro("STB_C_LEX_EQUAL_ARROW", "N");
        //  "&="  CLEX_andeq    "|="  CLEX_oreq     "^="  CLEX_xoreq
        stb_mod.addCMacro("STB_C_LEX_C_BITWISEEQ", "Y");
        //  "+="  CLEX_pluseq   "-="  CLEX_minuseq
        //  "*="  CLEX_muleq    "/="  CLEX_diveq    "%=" CLEX_modeq
        //  if both STB_C_LEX_SHIFTS & STB_C_LEX_ARITHEQ:
        //                      "<<=" CLEX_shleq    ">>=" CLEX_shreq
        stb_mod.addCMacro("STB_C_LEX_C_ARITHEQ", "Y");
        // letters after numbers are parsed as part of those numbers, and must be in suffix list below
        stb_mod.addCMacro("STB_C_LEX_PARSE_SUFFIXES", "N");
        // decimal integer suffixes e.g. "uUlL" -- these are returned as-is in string storage
        stb_mod.addCMacro("STB_C_LEX_DECIMAL_SUFFIXES", "\"\"");
        // e.g. "uUlL"
        stb_mod.addCMacro("STB_C_LEX_HEX_SUFFIXES", "\"\"");
        // e.g. "uUlL"
        stb_mod.addCMacro("STB_C_LEX_OCTAL_SUFFIXES", "\"\"");
        // e.g. "f"
        stb_mod.addCMacro("STB_C_LEX_FLOAT_SUFFIXES", "\"\"");
        // if Y, ends parsing at '\0'; if N, returns '\0' as token
        stb_mod.addCMacro("STB_C_LEX_0_IS_EOF", "Y");
        // parses integers as doubles so they can be larger than 'int', but only if STB_C_LEX_STDLIB==N
        stb_mod.addCMacro("STB_C_LEX_INTEGERS_AS_DOUBLES", "N");
        // allow newlines in double-quoted strings
        stb_mod.addCMacro("STB_C_LEX_MULTILINE_DSTRINGS", "N");
        // allow newlines in single-quoted strings
        stb_mod.addCMacro("STB_C_LEX_MULTILINE_SSTRINGS", "N");
        // use strtod,strtol for parsing #s; otherwise inaccurate hack
        stb_mod.addCMacro("STB_C_LEX_USE_STDLIB", "Y");
        // allow $ as an identifier character
        stb_mod.addCMacro("STB_C_LEX_DOLLAR_IDENTIFIER", "Y");
        // allow floats that have no decimal point if they have an exponent
        stb_mod.addCMacro("STB_C_LEX_FLOAT_NO_DECIMAL", "Y");
        // if Y, all CLEX_ token names are defined, even if never returned
        // leaving it as N should help you catch config bugs
        stb_mod.addCMacro("STB_C_LEX_DEFINE_ALL_TOKEN_NAMES", "N");

        // discard C-preprocessor directives (e.g. after prepocess
        // still have #line, #pragma, etc)
        //#define STB_C_LEX_ISWHITE(str)    ... // return length in bytes of whitespace characters if first char is whitespace
        // This line prevents the header file from replacing your definitions
        stb_mod.addCMacro("STB_C_LEX_DISCARD_PREPROCESSOR", "Y");
        stb_mod.addCMacro("STB_C_LEXER_DEFINITIONS", "1");
    }

    return stb_mod;
}
