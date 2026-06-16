const std = @import("std");
const Io = std.Io;

const gss = @import("gss");

pub fn main(init: std.process.Init) !void {
    var args = try init.minimal.args.iterateAllocator(init.gpa);
    std.debug.assert(args.skip());
    const gss_file = args.next() orelse @panic("TODO: handle no file name");

    const obj = try gss.loadFromFile(init.io, init.gpa, init.arena.allocator(), gss_file);

    std.debug.print("style.title.font_path: {s}\n", .{
        try obj.getValue([]const u8, &.{ "style", "title", "font_path" }),
    });

    std.debug.print("style.thumbnail.left: {d}\n", .{
        try obj.getValue(f64, &.{ "style", "thumbnail", "left" }),
    });
}
