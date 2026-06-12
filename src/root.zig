const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

pub const Value = union(enum) {
    object: Object,

    pub const Object = struct {
        items: []const struct {
            key: []const u8,
            value: Value,
        },
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

    pub fn getToken(l: *Lexer) c_int {
        return l.impl.stb_c_lexer_get_token();
    }

    pub fn getLocation(l: *Lexer, where: enum { first, last }) Location {
        var loc: Location = undefined;
        c.stb_c_lexer_get_location(l, switch (where) {
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

    pub fn expectToken(file_path: []const u8, l: *Lexer, expected: c_long) bool {
        l.getToken();
        if (l.impl.token != expected) {
            const loc = l.getLocation();
            std.debug.print("{s}:{d}:{d}: ERROR: Unexpected token. Expected {d}, but got {d}\n", .{ file_path, loc.line_number, loc.line_offset, expected, l.impl.token });
            return false;
        }
        return true;
    }
};

pub const Node = union(Kind) {
    pub const Kind = enum {
        object,
        value,
    };
};

pub fn loadFromFile(file_path: []const u8) void {
    std.debug.print("Input: \"{s}\"\n", .{file_path});
    var buf: [2048]u8 = undefined;
    var l: Lexer = .init(file_path, &buf);
    var i: usize = 0;
    while (true) : (i += 1) {
        const r = l.getToken();
        if (r == 0 or l.impl.token == 0) break;
        std.debug.print("r: {d}\n", .{r});
        const token_id = l.impl.token;
        const token: Lexer.Token = @enumFromInt(token_id);
        switch (token) {
            .id => std.debug.print("{s} (id)      =========================\n", .{l.impl.string}),
            .floatlit => std.debug.print("{d} (floatlit)\n", .{l.impl.real_number}),
            .dqstring => std.debug.print("{s} (dqstring)\n", .{l.impl.string}),
            _ => if (token_id < 0) {
                std.debug.print("{d} (error)\n", .{token_id});
                break;
            } else if (token_id < 256) {
                const c: u8 = @intCast(token_id);
                std.debug.print("{c} (char)\n", .{c});
            } else {
                std.debug.print("{d} (unknown)\n", .{token_id});
                break;
            },
            else => {
                std.debug.print("{d} ({t})\n", .{ token_id, token });
                break;
            },
        }
    }
    return;
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
