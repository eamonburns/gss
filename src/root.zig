const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

pub const Value = union(enum) {
    object: Object,
    float: f64,
    boolean: bool,
    string: []const u8,

    pub const Object = struct {
        items: []const Kvs,

        const Kvs = struct {
            key: []const u8,
            value: Value,
        };

        pub fn format(self: Object, writer: *Io.Writer) Io.Writer.Error!void {
            const v: Value = .{ .object = self };
            try v.format(writer);
        }
    };

    pub fn format(self: Value, writer: *Io.Writer) Io.Writer.Error!void {
        try self.dumpInner(writer, 0);
    }

    fn dumpInner(self: Value, writer: *Io.Writer, level: usize) Io.Writer.Error!void {
        switch (self) {
            .float => |float| try writer.print("{d}", .{float}),
            .boolean => |boolean| try writer.print("{}", .{boolean}),
            .string => |string| try writer.print("\"{s}\"", .{string}),
            .object => |object| {
                for (object.items) |kv| {
                    try writer.splatBytesAll("    ", level);
                    try writer.print("{s} = ", .{kv.key});
                    if (kv.value == .object) {
                        try writer.writeAll("{\n");
                        try kv.value.dumpInner(writer, level + 1);
                        try writer.splatBytesAll("    ", level);
                        try writer.writeByte('}');
                    } else {
                        try kv.value.dumpInner(writer, level + 1);
                    }
                    try writer.writeAll(",\n");
                }
            },
        }
    }
};

const Lexer = struct {
    impl: c.stb_lexer,

    const c = @import("stb_c_lexer");

    pub fn init(input: []const u8, string_store: []u8) Lexer {
        var l: c.stb_lexer = undefined;
        const input_ptr: usize = @intFromPtr(input.ptr);
        const end_ptr: usize = input_ptr + input.len;
        l.stb_c_lexer_init(input.ptr, @ptrFromInt(end_ptr), string_store.ptr, @intCast(string_store.len));
        return .{ .impl = l };
    }

    pub fn token(l: *const Lexer) Token {
        return @enumFromInt(l.impl.token);
    }

    pub fn string(l: *const Lexer) []const u8 {
        return l.impl.string[0..@intCast(l.impl.string_len)];
    }

    pub fn getToken(l: *Lexer) c_int {
        return l.impl.stb_c_lexer_get_token();
    }

    pub fn getLocation(l: *Lexer, where: enum { first, last }) Location {
        var loc: Location = undefined;
        c.stb_c_lexer_get_location(&l.impl, switch (where) {
            .first => l.impl.where_firstchar,
            .last => l.impl.where_lastchar,
        }, &loc);
        return loc;
    }

    pub const Location = c.stb_lex_location;
    pub const Token = enum(c_long) {
        eof = 256,
        parse_error = 257,
        intlit = 258,
        floatlit = 259,
        id = 260,
        dqstring = 261,
        sqstring = 262,
        charlit = 263,
        eq = 264,
        noteq = 265,
        lesseq = 266,
        greatereq = 267,
        andand = 268,
        oror = 269,
        shl = 270,
        shr = 271,
        plusplus = 272,
        minusminus = 273,
        pluseq = 274,
        minuseq = 275,
        muleq = 276,
        diveq = 277,
        modeq = 278,
        andeq = 279,
        oreq = 280,
        xoreq = 281,
        arrow = 282,
        eqarrow = 283,
        shleq = 284,
        shreq = 285,

        _,

        pub fn fromChar(char: u8) Token {
            return @enumFromInt(char);
        }

        pub fn format(
            self: Token,
            writer: *std.Io.Writer,
        ) std.Io.Writer.Error!void {
            switch (self) {
                else => |t| try writer.print("{t}", .{t}),
                _ => |t| switch (@intFromEnum(t)) {
                    1...255 => |d| {
                        const char: u8 = @intCast(d);
                        try writer.print("'{c}'", .{char});
                    },
                    else => |d| try writer.print("{d}", .{d}),
                },
            }
        }
    };
};

const Parser = struct {
    lexer: *Lexer,
    gpa: Allocator,
    arena: Allocator,

    pub fn init(gpa: Allocator, arena: Allocator, lexer: *Lexer) Parser {
        return .{
            .lexer = lexer,
            .gpa = gpa,
            .arena = arena,
        };
    }

    pub fn reportError(p: *Parser, file_path: []const u8, comptime format: []const u8, args: anytype) void {
        const loc = p.lexer.getLocation(.first);
        std.debug.print(
            "{s}:{d}:{d}: error: ",
            .{ file_path, loc.line_number, loc.line_offset },
        );
        std.debug.print(format ++ "\n", args);
    }

    pub const ParseError = error{
        ParseFailed,
        ExpectFailed,
    } || Allocator.Error;

    pub fn expectToken(p: *Parser, file_path: []const u8, expected: Lexer.Token) !void {
        const l = p.lexer;
        if (l.getToken() == 0) {
            p.reportError(file_path, "Expected token {f}, but reached end of input", .{expected});
            return error.ExpectFailed;
        }
        if (l.impl.token != @intFromEnum(expected)) {
            p.reportError(file_path, "Expected token {f}, but got {f}", .{ expected, l.token() });
            return error.ExpectFailed;
        }
    }

    pub fn parseValue(p: *Parser, file_path: []const u8) ParseError!Value {
        const l = p.lexer;
        if (l.getToken() == 0) {
            p.reportError(file_path, "Expected value, but reached end of input", .{});
            return error.ParseFailed;
        }
        switch (l.token()) {
            Lexer.Token.fromChar('{') => {
                const object = try p.parseObjectBody(file_path);
                try p.expectToken(file_path, .fromChar('}'));
                return .{ .object = object };
            },
            .floatlit => return .{
                .float = @floatCast(l.impl.real_number),
            },
            .id => {
                if (std.mem.eql(u8, "true", l.string())) {
                    return .{
                        .boolean = true,
                    };
                } else if (std.mem.eql(u8, "false", l.string())) {
                    return .{
                        .boolean = false,
                    };
                }
                p.reportError(file_path, "Unexpected identifier: {s}", .{l.string()});
                return error.ParseFailed;
            },
            .dqstring => return .{
                .string = try p.arena.dupe(u8, l.string()),
            },
            else => |t| {
                p.reportError(file_path, "invalid token: {t}", .{t});
                return error.ParseFailed;
            },
            _ => |t| {
                p.reportError(file_path, "invalid token: {f}", .{t});
                return error.ParseFailed;
            },
        }
    }

    pub fn parseObjectBody(p: *Parser, file_path: []const u8) ParseError!Value.Object {
        const l = p.lexer;
        var kvs: std.ArrayList(Value.Object.Kvs) = .empty;
        defer kvs.deinit(p.gpa); // NOTE: The kvs array doesn't live past this function. It is copied into an arena
        while (true) {
            const saved_l = l.*;
            if (l.getToken() == 0 or l.token() == Lexer.Token.fromChar('}') or l.token() == .eof) {
                // Don't consume the `}` token after the object body
                if (l.token() == Lexer.Token.fromChar('}')) l.* = saved_l;
                return .{
                    .items = try p.arena.dupe(Value.Object.Kvs, kvs.items),
                };
            }
            l.* = saved_l;

            try p.expectToken(file_path, .id);
            const key = try p.arena.dupe(u8, l.string());
            for (kvs.items) |kv| if (std.mem.eql(u8, kv.key, key)) {
                p.reportError(file_path, "Redefinition of field \"{s}\"", .{key});
                return error.ParseFailed;
            };
            try p.expectToken(file_path, .fromChar('='));
            const value = try p.parseValue(file_path);
            try kvs.append(p.gpa, .{ .key = key, .value = value });
            try p.expectToken(file_path, .fromChar(','));
        }
    }
};

pub const Node = union(Kind) {
    pub const Kind = enum {
        object,
        value,
    };
};

pub fn load(gpa: Allocator, arena: Allocator, input: []const u8, file_path: []const u8) !Value.Object {
    var string_store: [512]u8 = undefined;
    var l: Lexer = .init(input, &string_store);
    var p: Parser = .init(gpa, arena, &l);
    return try p.parseObjectBody(file_path);
}

pub fn loadFromFile(io: Io, gpa: Allocator, arena: Allocator, file_path: []const u8) !Value.Object {
    const input = blk: {
        const file = try Io.Dir.cwd().openFile(io, file_path, .{ .allow_directory = false });
        defer file.close(io);
        var file_buf: [1024]u8 = undefined;
        var file_reader = file.reader(io, &file_buf);
        const fw: *Io.Reader = &file_reader.interface;
        var aw: Io.Writer.Allocating = .init(gpa);
        _ = try fw.stream(&aw.writer, .unlimited);
        break :blk try aw.toOwnedSlice();
    };
    defer gpa.free(input);

    return load(gpa, arena, input, file_path);
}

test load {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    _ = try load(std.testing.allocator, arena.allocator(),
        \\foo = {},
    , "<string 1>");

    _ = try load(std.testing.allocator, arena.allocator(),
        \\foo = {
        \\  bar = "bla",
        \\},
        \\baz = 123.0,
        \\quux = {},
    , "<string 2>");

    _ = try load(std.testing.allocator, arena.allocator(),
        \\// vim: syntax=c ft=gss
        \\style = {
        \\    thumbnail = {
        \\        frame = true,
        \\        left = 0.59,
        \\        width = 0.14,
        \\        top = 0.20,
        \\        align = "center",
        \\        valign = "center",
        \\    },
        \\    title = {
        \\        top = 0.37,
        \\        left = 0.59, //style.thumbnail.left,
        \\        font_path = "./data/fonts/iosevka-bold.ttf",
        \\        font_size = 0.04,
        \\        align = "center",
        \\    },
        \\    link = {
        \\        top = 0.46,
        \\        left = 0.59, //style.thumbnail.left,
        \\        width = 0.1,
        \\        align = "center",
        \\    },
        \\},
    , "<string 3>");
}
