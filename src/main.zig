const std = @import("std");
const Io = std.Io;

const gss = @import("gss");

pub fn main(init: std.process.Init) !void {
    var args = try init.minimal.args.iterateAllocator(init.gpa);
    std.debug.assert(args.skip());
    const gss_file = args.next() orelse @panic("TODO: handle no file name");

    try gss.loadFromFile(init.io, init.gpa, gss_file);
}
