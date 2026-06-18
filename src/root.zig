const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const zig = std.zig;

pub const Value = union(enum) {
    float: f64,
    boolean: bool,
    string: []const u8,
    object: Object,
    expr: Expr,

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

    pub const Expr = union(Kind) {
        variable: struct {
            path: []const []const u8,
        },

        pub const Kind = enum {
            variable,
        };
    };

    pub fn format(self: Value, writer: *Io.Writer) Io.Writer.Error!void {
        try self.formatInner(&self, writer, 0);
    }

    fn formatInner(self: Value, root: *const Value, writer: *Io.Writer, level: usize) Io.Writer.Error!void {
        switch (self) {
            .float => |float| try writer.print("{d}", .{float}),
            .boolean => |boolean| try writer.print("{}", .{boolean}),
            .string => |string| try writer.print("\"{s}\"", .{string}),
            .object => |object| {
                // FIXME: Don't print \n at the end
                for (object.items) |kv| {
                    try writer.splatBytesAll("    ", level);
                    try writer.print("{s} = ", .{kv.key});
                    if (kv.value == .object) {
                        try writer.writeAll("{\n");
                        try kv.value.formatInner(root, writer, level + 1);
                        try writer.splatBytesAll("    ", level);
                        try writer.writeByte('}');
                    } else {
                        try kv.value.formatInner(root, writer, level + 1);
                    }
                    try writer.writeAll(",\n");
                }
            },
            .expr => |expr| switch (expr) {
                .variable => |v| {
                    const value = root.getValue(v.path) catch |err| switch (err) {
                        error.StackOverflow => return writer.writeAll("[recursive]"),
                        error.Missing => return writer.writeAll("[missing]"),
                    };
                    if (value == .object) {
                        try writer.writeAll("{\n");
                        try value.formatInner(root, writer, level + 1);
                        try writer.splatBytesAll("    ", level);
                        try writer.writeByte('}');
                    } else {
                        try value.formatInner(root, writer, level + 1);
                    }
                },
            },
        }
    }

    pub const GetFallbackError = GetValueFallbackError || error{
        TypeMismatch,
    };
    pub fn getFallback(self: Value, comptime T: type, fallback: T, path: []const []const u8) GetFallbackError!T {
        return self.get(T, path) catch |err| switch (err) {
            error.Missing => fallback,
            else => |e| e,
        };
    }

    pub const GetError = GetValueError || error{
        TypeMismatch,
    };
    pub fn get(self: Value, comptime T: type, path: []const []const u8) GetError!T {
        const value = try self.getValue(path);

        switch (T) {
            Object => if (value == .object) {
                return value.object;
            } else return error.TypeMismatch,
            f64 => if (value == .float) {
                return value.float;
            } else return error.TypeMismatch,
            bool => if (value == .boolean) {
                return value.boolean;
            } else return error.TypeMismatch,
            []const u8 => if (value == .string) {
                return value.string;
            } else return error.TypeMismatch,
            else => @compileError("invalid type: " ++ @typeName(T)),
        }
    }

    pub const GetValueFallbackError = error{StackOverflow};
    pub fn getValueFallback(self: Value, fallback: Value, path: []const []const u8) GetValueFallbackError!Value {
        return self.getValue(path) catch |err| switch (err) {
            error.Missing => fallback,
            else => |e| e,
        };
    }

    pub const GetValueError = error{ Missing, StackOverflow };
    pub fn getValue(self: Value, path: []const []const u8) GetValueError!Value {
        return self.getValueInner(path, 0);
    }

    fn getValueInner(self: Value, path: []const []const u8, level: usize) GetValueError!Value {
        const recursion_limit = 100; // TODO: Make configurable?
        if (level > recursion_limit) return error.StackOverflow;

        var cursor = self;
        for (path) |segment| {
            const object = switch (cursor) {
                else => {
                    return error.Missing;
                },
                .object => |o| o,
            };
            cursor = for (object.items) |kv| {
                if (std.mem.eql(u8, segment, kv.key)) break kv.value;
            } else return error.Missing;
        }

        const expr = switch (cursor) {
            .expr => |e| e,
            else => return cursor,
        };

        switch (expr) {
            .variable => |v| return self.getValueInner(v.path, level + 1),
        }
    }
};

const Parser = struct {
    source: [:0]const u8,
    tokenizer: zig.Tokenizer,
    gpa: Allocator,
    arena: Allocator,

    pub fn init(gpa: Allocator, arena: Allocator, source: [:0]const u8) Parser {
        return .{
            .source = source,
            .tokenizer = .init(source),
            .gpa = gpa,
            .arena = arena,
        };
    }

    pub fn tokenSlice(p: *Parser, token: zig.Token) []const u8 {
        return p.source[token.loc.start..token.loc.end];
    }

    /// Report an error, in the format:
    ///
    /// ```
    /// <file_path>:<token.line>:<token.column>: error: <format>
    ///     <token.source_line>
    ///                ^^^
    /// ```
    ///
    /// (Where `^^^` points at `token`)
    pub fn reportError(p: *Parser, file_path: []const u8, token: zig.Token, comptime format: []const u8, args: anytype) void {
        const loc = zig.findLineColumn(p.source, token.loc.start);
        std.debug.print("{s}:{d}:{d}: error: ", .{ file_path, loc.line, loc.column });
        std.debug.print(format ++ "\n", args);
        std.debug.print("    {s}\n", .{loc.source_line});
        std.debug.print("    ", .{});
        for (0..loc.column) |_| std.debug.print(" ", .{});
        for (0..token.loc.end - token.loc.start) |_| std.debug.print("^", .{});
        std.debug.print("\n", .{});
    }

    pub const ParseError = error{
        ParseFailed,
        ExpectFailed,
    } || Allocator.Error;

    pub fn expectToken(p: *Parser, file_path: []const u8, expected: zig.Token.Tag) !zig.Token {
        const tok = p.tokenizer.next();
        // HACK: treat keywords as identifiers
        if (tok.tag != expected and expected != .identifier) {
            p.reportError(file_path, tok, "Expected token {t}, but got {t}", .{ expected, tok.tag });
            return error.ExpectFailed;
        } else if (tok.tag != expected) switch (tok.tag) {
            // If we are in this switch statement, it is because tok.tag != expected, and expected == .identifier

            // zig fmt: off
            .keyword_addrspace,   .keyword_align,   .keyword_allowzero,   .keyword_and,
            .keyword_anyframe,    .keyword_anytype, .keyword_asm,         .keyword_break,
            .keyword_callconv,    .keyword_catch,   .keyword_comptime,    .keyword_const,
            .keyword_continue,    .keyword_defer,   .keyword_else,        .keyword_enum,
            .keyword_errdefer,    .keyword_error,   .keyword_export,      .keyword_extern,
            .keyword_fn,          .keyword_for,     .keyword_if,          .keyword_inline,
            .keyword_linksection, .keyword_noalias, .keyword_noinline,    .keyword_nosuspend,
            .keyword_opaque,      .keyword_or,      .keyword_orelse,      .keyword_packed,
            .keyword_pub,         .keyword_resume,  .keyword_return,      .keyword_struct,
            .keyword_suspend,     .keyword_switch,  .keyword_test,        .keyword_threadlocal,
            .keyword_try,         .keyword_union,   .keyword_unreachable, .keyword_var,
            .keyword_volatile,    .keyword_while,
            // zig fmt: on
            => {
                // HACK: Keywords are treated as identifiers
                return tok;
            },
            else => {
                p.reportError(file_path, tok, "Expected token {t}, but got {t}", .{ expected, tok.tag });
                return error.ExpectFailed;
            },
        };
        return tok;
    }

    pub fn parseValue(p: *Parser, file_path: []const u8) ParseError!Value {
        const tok = p.tokenizer.next();
        switch (tok.tag) {
            .eof => {
                p.reportError(file_path, tok, "Expected value, but reached end of input", .{});
                return error.ParseFailed;
            },
            .l_brace => {
                const object = try p.parseObjectBody(file_path);
                _ = try p.expectToken(file_path, .r_brace);
                return .{ .object = object };
            },
            .number_literal => {
                const f = std.fmt.parseFloat(f64, p.tokenSlice(tok)) catch {
                    p.reportError(file_path, tok, "invalid number literal", .{});
                    return error.ParseFailed;
                };
                return .{ .float = f };
            },
            // Annoying side effect of using the Zig parser, have to handle keywords
            // zig fmt: off
            .identifier,          .keyword_addrspace,   .keyword_align,   .keyword_allowzero,
            .keyword_and,         .keyword_anyframe,    .keyword_anytype, .keyword_asm,
            .keyword_break,       .keyword_callconv,    .keyword_catch,   .keyword_comptime,
            .keyword_const,       .keyword_continue,    .keyword_defer,   .keyword_else,
            .keyword_enum,        .keyword_errdefer,    .keyword_error,   .keyword_export,
            .keyword_extern,      .keyword_fn,          .keyword_for,     .keyword_if,
            .keyword_inline,      .keyword_linksection, .keyword_noalias, .keyword_noinline,
            .keyword_nosuspend,   .keyword_opaque,      .keyword_or,      .keyword_orelse,
            .keyword_packed,      .keyword_pub,         .keyword_resume,  .keyword_return,
            .keyword_struct,      .keyword_suspend,     .keyword_switch,  .keyword_test,
            .keyword_threadlocal, .keyword_try,         .keyword_union,   .keyword_unreachable,
            .keyword_var,         .keyword_volatile,    .keyword_while,
            // zig fmt: on
            => {
                if (std.mem.eql(u8, "true", p.tokenSlice(tok))) {
                    return .{ .boolean = true };
                } else if (std.mem.eql(u8, "false", p.tokenSlice(tok))) {
                    return .{ .boolean = false };
                }

                var path: std.ArrayList([]const u8) = .empty;
                defer path.deinit(p.gpa);
                try path.append(p.gpa, try p.arena.dupe(u8, p.tokenSlice(tok)));

                var saved_tokenizer = p.tokenizer;
                while (p.tokenizer.next().tag == .period) {
                    const id = try p.expectToken(file_path, .identifier);
                    try path.append(p.gpa, try p.arena.dupe(u8, p.tokenSlice(id)));
                    saved_tokenizer = p.tokenizer;
                }
                p.tokenizer = saved_tokenizer;

                const expr: Value.Expr = .{ .variable = .{
                    .path = try p.arena.dupe([]const u8, path.items),
                } };

                return .{ .expr = expr };
            },
            .string_literal => {
                var aw: Io.Writer.Allocating = try .initCapacity(p.arena, tok.loc.end - tok.loc.start);
                const result = zig.string_literal.parseWrite(&aw.writer, p.tokenSlice(tok)) catch return error.OutOfMemory;
                switch (result) {
                    .failure => |err| {
                        p.reportError(file_path, tok, "unable to parse string: {f}", .{err.fmt(p.tokenSlice(tok))});
                        return error.ParseFailed;
                    },
                    .success => {},
                }
                return .{
                    // NOTE: In the optimistic case, where the parsed string is
                    // shorter than the string literal, this should not pollute
                    // the arena with garbage allocations.
                    .string = try aw.toOwnedSlice(),
                };
            },
            else => {
                p.reportError(file_path, tok, "invalid token: {t}", .{tok.tag});
                return error.ParseFailed;
            },
        }
    }

    pub fn parseObjectBody(p: *Parser, file_path: []const u8) ParseError!Value.Object {
        var kvs: std.ArrayList(Value.Object.Kvs) = .empty;
        defer kvs.deinit(p.gpa); // NOTE: The kvs array doesn't live past this function. It is copied into an arena

        while (true) {
            {
                const saved_tokenizer = p.tokenizer;
                const tok = p.tokenizer.next();
                defer p.tokenizer = saved_tokenizer;

                if (tok.tag == .r_brace or tok.tag == .eof) {
                    return .{
                        .items = try p.arena.dupe(Value.Object.Kvs, kvs.items),
                    };
                }
            }

            const id = try p.expectToken(file_path, .identifier);
            const key = try p.arena.dupe(u8, p.tokenSlice(id));
            for (kvs.items) |kv| if (std.mem.eql(u8, kv.key, key)) {
                p.reportError(file_path, id, "Redefinition of field \"{s}\"", .{key});
                return error.ParseFailed;
            };
            _ = try p.expectToken(file_path, .equal);
            const value = try p.parseValue(file_path);
            try kvs.append(p.gpa, .{ .key = key, .value = value });
            _ = try p.expectToken(file_path, .comma);
        }
    }
};

pub const Node = union(Kind) {
    pub const Kind = enum {
        object,
        value,
    };
};

pub fn load(gpa: Allocator, arena: Allocator, input: [:0]const u8, file_path: []const u8) !Value {
    var p: Parser = .init(gpa, arena, input);
    return .{
        .object = try p.parseObjectBody(file_path),
    };
}

pub fn loadFromFile(io: Io, gpa: Allocator, arena: Allocator, file_path: []const u8) !Value {
    const input = try Io.Dir.cwd().readFileAllocOptions(io, file_path, gpa, .unlimited, .of(u8), 0);
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
        \\baz = 123,
        \\quux = {},
    , "<string 2>");

    _ = try load(std.testing.allocator, arena.allocator(),
        \\// vim: syntax=c ft=casl
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

test "Value.getValue" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const value = try load(std.testing.allocator, arena.allocator(),
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
        \\        left = style.thumbnail.left,
        \\        font_path = "./data/fonts/iosevka-bold.ttf",
        \\        font_size = 0.04,
        \\        align = "center",
        \\    },
        \\    link = {
        \\        top = 0.46,
        \\        left = 0.59,
        \\        width = 0.1,
        \\        align = "center",
        \\    },
        \\},
        \\bla = 123,
    , "<string 1>");

    try std.testing.expectEqual(
        123,
        try value.get(f64, &.{"bla"}),
    );

    try std.testing.expectEqualStrings(
        "center",
        try value.get([]const u8, &.{ "style", "link", "align" }),
    );
    try std.testing.expectEqual(
        0.04,
        try value.get(f64, &.{ "style", "title", "font_size" }),
    );
    try std.testing.expectEqual(
        true,
        try value.get(bool, &.{ "style", "thumbnail", "frame" }),
    );

    try std.testing.expectEqual(
        0.59,
        try value.get(f64, &.{ "style", "title", "left" }),
    );
}
