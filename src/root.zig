const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

pub const Value = union(enum) {
    object: Object,

    pub const Object = struct {
        items: []const Kvs,

        const Kvs = struct {
            key: []const u8,
            value: Value,
        };
    };
};

const Lexer = struct {
    impl: c.stb_lexer,

    const c = @import("stb_c_lexer");

    pub fn init(input: []const u8, string_store: []u8) Lexer {
        var l: c.stb_lexer = undefined;
        const input_ptr: usize = @intFromPtr(input.ptr);
        const end_ptr: usize = input_ptr + input.len;
        l.stb_c_lexer_init(input.ptr, @ptrFromInt(input_ptr + end_ptr), string_store.ptr, @intCast(string_store.len));
        return .{ .impl = l };
    }

    pub fn token(l: *const Lexer) Token {
        return @enumFromInt(l.impl.token);
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
            // const long: c_long = @intCast(char);
            return @enumFromInt(char);
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

    pub fn expectToken(p: *Parser, file_path: []const u8, expected: Lexer.Token) !void {
        const l = p.lexer;
        if (l.getToken() == 0) {
            p.reportError(file_path, "Expected token {d}, but reach end of input", .{expected});
            return error.ExpectFailed;
        }
        if (l.impl.token != @intFromEnum(expected)) {
            p.reportError(file_path, "Expected token {d}, but got {d}", .{ expected, l.impl.token });
            // const loc = l.getLocation(.first);
            // std.debug.print("{s}:{d}:{d}: ERROR: Unexpected token. Expected {d}, but got {d}\n", .{ file_path, loc.line_number, loc.line_offset, expected, l.impl.token });
            return error.ExpectFailed;
        }
    }

    pub fn parseValue(p: *Parser, file_path: []const u8) !Value {
        _ = p;
        _ = file_path;
        @panic("TODO: implement " ++ @src().fn_name);
    }

    pub fn parseObjectBody(p: *Parser, file_path: []const u8) !Value.Object {
        const l = p.lexer;
        var kvs: std.ArrayList(Value.Object.Kvs) = .empty;
        while (true) {
            const saved_l = l.*;
            if (l.getToken() == 0 or l.token() == Lexer.Token.fromChar('}') or l.token() == .eof) {
                return .{
                    .items = try kvs.toOwnedSlice(p.gpa),
                };
            }
            l.* = saved_l;

            try p.expectToken(file_path, .id);
            const key = try p.arena.dupe(u8, l.impl.string[0..@intCast(l.impl.string_len)]);
            for (kvs.items) |kv| if (std.mem.eql(u8, kv.key, key)) {
                p.reportError(file_path, "Redefinition of field \"{s}\"", .{key});
                return error.DuplicateKey;
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

pub fn loadFromFile(io: Io, gpa: Allocator, file_path: []const u8) !void {
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

    var string_store: [128]u8 = undefined;
    var l: Lexer = .init(input, &string_store);
    var arena: std.heap.ArenaAllocator = .init(gpa);
    var p: Parser = .init(gpa, arena.allocator(), &l);
    _ = try p.parseObjectBody(file_path);
}

test {
    var string_store: [20]u8 = undefined;
    var l: Lexer = .init("hi", &string_store);

    try std.testing.expect(l.getToken());
    std.debug.print(
        \\token:
        \\  token: {d} ({u})
        \\  real_number: {d}
        \\  int_number: {d}
        \\  string: "{s}"
        \\  string_len: {d}
        \\
        \\
    , .{
        l.impl.token,
        @as(u21, @intCast(l.impl.token)),
        l.impl.real_number,
        l.impl.int_number,
        l.impl.string,
        l.impl.string_len,
    });
}
