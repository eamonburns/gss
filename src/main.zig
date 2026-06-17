const std = @import("std");
const Io = std.Io;

const gss = @import("gss");

pub fn main(init: std.process.Init) !void {
    var args = try init.minimal.args.iterateAllocator(init.gpa);
    std.debug.assert(args.skip());
    const gss_file = args.next() orelse @panic("TODO: handle no file name");

    const value = try gss.loadFromFile(init.io, init.gpa, init.arena.allocator(), gss_file);
    std.debug.print("{f}", .{value});
}
