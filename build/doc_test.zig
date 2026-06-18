const std = @import("std");

const casl = @import("casl");

pub fn main(init: std.process.Init) !void {
    var args = try init.minimal.args.iterateAllocator(init.gpa);
    _ = args.skip(); // exe name

    while (args.next()) |doc_file| {
        const file_data = try std.Io.Dir.cwd().readFileAlloc(init.io, doc_file, init.gpa, .unlimited);
        defer init.gpa.free(file_data);

        const start_marker = "\n```c casl\n";
        const end_marker = "\n```\n";

        var pos: usize = 0;
        var i: usize = 0;
        while (std.mem.findPos(u8, file_data, pos, start_marker)) |start_idx| : (i += 1) {
            const line_number = blk: {
                const loc = std.zig.findLineColumn(file_data, start_idx);
                break :blk loc.line + 1;
            };
            const file_path = try std.fmt.allocPrint(init.gpa, "{s}({d})", .{ doc_file, line_number });
            defer init.gpa.free(file_path);

            const source_start = start_idx + start_marker.len;
            if (std.mem.findPos(u8, file_data, source_start, end_marker)) |end_idx| {
                const source = try init.gpa.dupeZ(u8, file_data[start_idx + start_marker.len .. end_idx + 1]);
                defer init.gpa.free(source);
                pos = end_idx + end_marker.len;

                // Pseudo file path (because there are multiple sources per file)
                _ = casl.load(init.gpa, init.arena.allocator(), source, file_path) catch |err| switch (err) {
                    error.OutOfMemory => return error.OutOfMemory,
                    else => |e| std.debug.print("{s}: error: {t}\n", .{ file_path, e }),
                };
                std.debug.print("{s}: validated\n", .{file_path});
            } else {
                std.debug.print("{s}: error: no end marker\n", .{file_path});
            }
        }
    }
}
