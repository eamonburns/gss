const std = @import("std");
const Io = std.Io;

const casl = @import("casl");

pub fn main(init: std.process.Init) void {
    const io = init.io;
    const gpa = init.gpa;
    const arena = init.arena.allocator();

    var args = init.minimal.args.iterateAllocator(init.gpa) catch |err| {
        std.debug.print("casl: error: {t}\n", .{err});
        std.process.exit(1);
    };
    const arg0 = args.next() orelse "casl";

    const cmd: Cmd = .parse(arg0, &args);

    // TODO: Rename this (unfortunately, casl is taken...)
    const value = casl.loadFromFile(io, gpa, arena, cmd.file) catch |err| switch (err) {
        error.OutOfMemory => Cmd.oom(arg0),
        error.ParseFailed, error.ExpectFailed => Cmd.fatal(arg0, "unable to parse file", .{}),
        error.FileNotFound => Cmd.fatal(arg0, "file not found", .{}),
        else => |e| Cmd.fatal(arg0, "unknown: {t}", .{e}),
    };

    if (cmd.query) |query_str| {
        const query = casl.load(gpa, arena, query_str, cmd.file) catch |err| switch (err) {
            error.OutOfMemory => Cmd.oom(arg0),
            error.ParseFailed, error.ExpectFailed => Cmd.fatal(arg0, "unable to parse query", .{}),
        };

        const result = query.resolveInner(
            arena,
            &value,
            &.{ .casl = &query },
        ) catch |err| switch (err) {
            error.OutOfMemory => Cmd.oom(arg0),
        };

        std.debug.print("{f}\n", .{result});
    } else {
        std.debug.print(
            \\---
            \\{f}
            \\---
            \\
        , .{value});

        repl(io, gpa, value) catch |err| switch (err) {
            error.OutOfMemory => Cmd.oom(arg0),
            else => |e| Cmd.fatal(arg0, "unknown: {t}", .{e}),
        };
    }
}

/// Struct to assist in parsing the command line
const Cmd = struct {
    file: []const u8,
    query: ?[:0]const u8,

    pub fn parse(arg0: []const u8, args: *std.process.Args.Iterator) Cmd {
        const file = args.next() orelse fatal(arg0, "<file> is required", .{});
        if (std.mem.eql(u8, file, "--help") or std.mem.eql(u8, file, "-h")) {
            exitHelp(arg0, 0);
        }
        return .{
            .file = file,
            .query = args.next(),
        };
    }

    fn fatal(arg0: []const u8, comptime fmt: []const u8, args: anytype) noreturn {
        std.debug.print("{s}: error: ", .{arg0});
        std.debug.print(fmt ++ "\n", args);
        std.process.exit(1);
    }

    fn oom(arg0: []const u8) noreturn {
        fatal(arg0, "out of memory", .{});
    }

    fn exitHelp(arg0: []const u8, status: u8) noreturn {
        std.debug.print(
            \\usage: {s} <file> [query]
            \\
            \\Parameters:
            \\  <file>   Name of Casl file.
            \\  [query]  Optional query. If not provided, the REPL will be started.
            \\
        , .{arg0});
        std.process.exit(status);
    }
};

fn repl(io: Io, gpa: std.mem.Allocator, value: casl.Casl) !void {
    var arena_instance: std.heap.ArenaAllocator = .init(gpa);
    defer arena_instance.deinit();
    const arena = arena_instance.allocator();

    const stdin_file = Io.File.stdin();
    var stdin_buf: [1024]u8 = undefined;
    var stdin_reader = stdin_file.reader(io, &stdin_buf);
    const input = &stdin_reader.interface;
    std.debug.print("> ", .{});
    repl: while (try input.takeDelimiter('\n')) |query_str| : (std.debug.print("> ", .{})) {
        _ = arena_instance.reset(.retain_capacity);

        const query = casl.load(gpa, arena, try arena.dupeZ(u8, query_str), "<repl>") catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.ParseFailed, error.ExpectFailed => {
                std.debug.print("error: unable to parse query\n", .{});
                continue :repl;
            },
        };

        const result = query.resolveInner(
            arena,
            &value,
            &.{ .casl = &query },
        ) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
        };

        std.debug.print("{f}\n", .{result});
    }
    std.debug.print("\n", .{});
}
