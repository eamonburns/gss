const std = @import("std");
const Io = std.Io;

const casl = @import("casl");

const FileExt = enum {
    casl,
    md,
};

pub fn main(init: std.process.Init) !void {
    var args = try init.minimal.args.iterateAllocator(init.gpa);
    _ = args.skip(); // exe name

    while (args.next()) |doc_file| {
        const ext = blk: {
            const idx = std.mem.findScalarLast(u8, doc_file, '.') orelse {
                std.debug.print("{s}: error: no file extension\n", .{doc_file});
                continue;
            };
            break :blk std.meta.stringToEnum(FileExt, doc_file[idx + 1 .. doc_file.len]) orelse {
                std.debug.print("{s}: error: invalid file extension\n", .{doc_file});
                continue;
            };
        };

        switch (ext) {
            .md => testMarkdownFile(init.io, init.gpa, doc_file),
            .casl => testCaslFile(init.io, init.gpa, doc_file),
        }
    }
}

fn testMarkdownFile(io: Io, gpa: std.mem.Allocator, doc_file: []const u8) void {
    const file_data = std.Io.Dir.cwd().readFileAlloc(io, doc_file, gpa, .unlimited) catch |err| {
        std.debug.print("{s}: error: unable to open file: {t}\n", .{ doc_file, err });
        return;
    };
    defer gpa.free(file_data);

    const start_marker = "\n```c casl\n";
    const end_marker = "\n```\n";

    var pos: usize = 0;
    var i: usize = 0;
    while (std.mem.findPos(u8, file_data, pos, start_marker)) |start_idx| : (i += 1) {
        const line_number = blk: {
            // `start_idx` points at the newline before the ```
            const loc = std.zig.findLineColumn(file_data, start_idx + 1);
            break :blk loc.line + 1;
        };
        // Pseudo file path (because there are multiple sources per file)
        const file_path = std.fmt.allocPrint(gpa, "{s}({d})", .{ doc_file, line_number }) catch |err| {
            std.debug.print("{s}: error: {t}", .{ doc_file, err });
            return;
        };
        defer gpa.free(file_path);

        const source_start = start_idx + start_marker.len;
        if (std.mem.findPos(u8, file_data, source_start, end_marker)) |end_idx| {
            const source = gpa.dupeZ(u8, file_data[start_idx + start_marker.len .. end_idx + 1]) catch |err| {
                std.debug.print("{s}: error: {t}", .{ doc_file, err });
                return;
            };
            defer gpa.free(source);
            pos = end_idx + end_marker.len;

            var arena: std.heap.ArenaAllocator = .init(gpa);
            defer arena.deinit();
            _ = casl.load(gpa, arena.allocator(), source, file_path) catch |err| {
                std.debug.print("{s}: error: {t}\n", .{ file_path, err });
                continue;
            };
            std.debug.print("{s}: validated\n", .{file_path});
        } else {
            std.debug.print("{s}: error: no end marker\n", .{file_path});
        }
    }
}

fn testCaslFile(io: Io, gpa: std.mem.Allocator, doc_file: []const u8) void {
    const source = std.Io.Dir.cwd().readFileAllocOptions(io, doc_file, gpa, .unlimited, .of(u8), 0) catch |err| {
        std.debug.print("{s}: error: unable to open file: {t}\n", .{ doc_file, err });
        return;
    };
    defer gpa.free(source);

    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    _ = casl.load(gpa, arena.allocator(), source, doc_file) catch |err| {
        std.debug.print("{s}: error: {t}\n", .{ doc_file, err });
        return;
    };
    std.debug.print("{s}: validated\n", .{doc_file});
}
