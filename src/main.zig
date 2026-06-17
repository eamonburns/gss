const std = @import("std");
const Io = std.Io;

const casl = @import("casl");

pub fn main(init: std.process.Init) !void {
    var args = try init.minimal.args.iterateAllocator(init.gpa);
    std.debug.assert(args.skip());
    const casl_file = args.next() orelse @panic("TODO: handle no file name");

    const value = try casl.loadFromFile(init.io, init.gpa, init.arena.allocator(), casl_file);
    std.debug.print("{f}", .{value});

    const sections: []const []const u8 = &.{
        "screen",
        "sign",
        "timer",
        "thumbnail",
        "title",
        "link",
        "logo",
    };
    for (sections) |section| {
        const frame = try value.getFallback(bool, false, &.{ "style", section, "frame" });
        std.debug.print("style.{s}.frame = {}\n", .{ section, frame });
        if (value.get([]const u8, &.{ "style", section, "font_path" })) |font_path| {
            std.debug.print("style.{s}.font_path = \"{s}\"\n", .{ section, font_path });
        } else |err| switch (err) {
            error.Missing => {},
            else => |e| return e,
        }
    }
}
