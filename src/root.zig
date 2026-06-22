const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const zig = std.zig;

pub const Casl = union(enum) {
    value: Value,
    expr: Expr,

    pub const Expr = union(enum) {
        variable: struct {
            path: []const []const u8,
        },
        object: Object,

        pub const Object = struct {
            items: []const Kvs,

            const Kvs = struct {
                key: []const u8,
                value: Casl,
            };
        };
    };

    pub fn resolvePath(root: Casl, arena: Allocator, path: []const []const u8) Allocator.Error!Value {
        const casl: Casl = .{ .expr = .{ .variable = .{ .path = path } } };
        return resolveInner(&casl, arena, &root, &.{ .casl = &casl });
    }

    pub fn resolve(casl: Casl, arena: Allocator) Allocator.Error!Value {
        return resolveInner(&casl, arena, &casl, &.{ .casl = &casl });
    }
    pub fn resolveInner(casl: *const Casl, arena: Allocator, root: *const Casl, stack: *const Stack) Allocator.Error!Value {
        const expr = switch (casl.*) {
            .value => |v| return v,
            .expr => |e| e,
        };

        switch (expr) {
            .object => |obj| {
                const resolved_items = try arena.alloc(Value.Object.Kvs, obj.items.len);
                for (obj.items, resolved_items) |*obj_kv, *resolved_kv| {
                    resolved_kv.key = try arena.dupe(u8, obj_kv.key);
                    const new_stack = stack.push(&obj_kv.value) catch return .recursive;
                    resolved_kv.value = try obj_kv.value.resolveInner(arena, root, &new_stack);
                }
                return .{ .object = .{ .items = resolved_items } };
            },
            .variable => |v| {
                var cursor = root;
                for (v.path) |segment| {
                    if (cursor.* != .expr or cursor.expr != .object) {
                        return .missing;
                    }
                    const object = cursor.expr.object;
                    cursor = for (object.items) |*kv| {
                        if (std.mem.eql(u8, segment, kv.key)) break &kv.value;
                    } else return .missing;
                }

                const new_stack = stack.push(cursor) catch return .recursive;
                return cursor.resolveInner(arena, root, &new_stack);
            },
        }
    }

    const Stack = struct {
        casl: *const Casl,
        parent: ?*const Stack = null,

        pub fn push(self: *const Stack, casl: *const Casl) !Stack {
            var cursor = self;
            while (cursor.parent) |parent| {
                if (parent.casl == casl) return error.Recursive;
                cursor = parent;
            }

            return .{
                .casl = casl,
                .parent = self,
            };
        }
    };

    pub fn format(
        self: Casl,
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        return self.formatInner(writer, 0);
    }

    pub fn formatInner(self: Casl, writer: *std.Io.Writer, level: usize) std.Io.Writer.Error!void {
        const indent = "  "; // TODO: Make configurable?
        switch (self) {
            .value => |v| try v.formatInner(writer, level),
            .expr => |e| switch (e) {
                .variable => |variable| {
                    for (variable.path, 0..) |segment, i| {
                        if (i != 0) try writer.writeByte('.');
                        try writer.writeAll(segment);
                    }
                },
                .object => |object| {
                    for (object.items, 0..) |kv, i| {
                        try writer.splatBytesAll(indent, level);
                        try writer.print("{s} = ", .{kv.key});
                        if (kv.value == .expr and kv.value.expr == .object) {
                            if (kv.value.expr.object.items.len == 0) {
                                try writer.writeAll("{}");
                            } else {
                                try writer.writeAll("{\n");
                                try kv.value.formatInner(writer, level + 1);
                                try writer.writeByte('\n');
                                try writer.splatBytesAll(indent, level);
                                try writer.writeAll("}");
                            }
                        } else {
                            try kv.value.formatInner(writer, level + 1);
                        }
                        try writer.writeByte(',');
                        // Newline after all but the last item
                        if (i != object.items.len - 1) try writer.writeByte('\n');
                    }
                },
            },
        }
    }
};

pub const Value = union(enum) {
    float: f64,
    boolean: bool,
    string: []const u8,
    object: Object,
    err: Error,

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

    pub const Error = error{ Recursive, Missing };

    pub const recursive: Value = .{ .err = error.Recursive };
    pub const missing: Value = .{ .err = error.Missing };

    pub fn format(self: Value, writer: *Io.Writer) Io.Writer.Error!void {
        try self.formatInner(writer, 0);
    }

    fn formatInner(self: Value, writer: *Io.Writer, level: usize) Io.Writer.Error!void {
        const indent = "  "; // TODO: Make configurable?
        switch (self) {
            .float => |float| try writer.print("{d}", .{float}),
            .boolean => |boolean| try writer.print("{}", .{boolean}),
            .string => |string| try writer.print("\"{s}\"", .{string}),
            .object => |object| {
                for (object.items, 0..) |kv, i| {
                    try writer.splatBytesAll(indent, level);
                    try writer.print("{s} = ", .{kv.key});
                    if (kv.value == .object) {
                        if (kv.value.object.items.len == 0) {
                            try writer.writeAll("{}");
                        } else {
                            try writer.writeAll("{\n");
                            try kv.value.formatInner(writer, level + 1);
                            try writer.writeByte('\n');
                            try writer.splatBytesAll(indent, level);
                            try writer.writeAll("}");
                        }
                    } else {
                        try kv.value.formatInner(writer, level + 1);
                    }
                    try writer.writeByte(',');
                    // Newline after all but the last item
                    if (i != object.items.len - 1) try writer.writeByte('\n');
                }
            },
            .err => |e| switch (e) {
                error.Missing => try writer.writeAll("[missing]"),
                error.Recursive => try writer.writeAll("[recursive]"),
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

        return cursor;
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
            p.reportError(file_path, tok, "Expected {t}, but got {t}", .{ expected, tok.tag });
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

    pub fn parseCasl(p: *Parser, file_path: []const u8) ParseError!Casl {
        const tok = p.tokenizer.next();
        switch (tok.tag) {
            .eof => {
                p.reportError(file_path, tok, "Expected value, but reached end of input", .{});
                return error.ParseFailed;
            },
            .l_brace => {
                const object = try p.parseObjectBody(file_path);
                _ = try p.expectToken(file_path, .r_brace);
                return .{ .expr = .{ .object = object } };
            },
            .number_literal => {
                const f = std.fmt.parseFloat(f64, p.tokenSlice(tok)) catch {
                    p.reportError(file_path, tok, "invalid number literal", .{});
                    return error.ParseFailed;
                };
                return .{ .value = .{ .float = f } };
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
                    return .{ .value = .{ .boolean = true } };
                } else if (std.mem.eql(u8, "false", p.tokenSlice(tok))) {
                    return .{ .value = .{ .boolean = false } };
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

                const expr: Casl.Expr = .{ .variable = .{
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
                    .value = .{
                        // NOTE: In the optimistic case, where the parsed string is
                        // shorter than the string literal, this should not pollute
                        // the arena with garbage allocations.
                        .string = try aw.toOwnedSlice(),
                    },
                };
            },
            else => {
                p.reportError(file_path, tok, "invalid token: {t}", .{tok.tag});
                return error.ParseFailed;
            },
        }
    }

    pub fn parseObjectBody(p: *Parser, file_path: []const u8) ParseError!Casl.Expr.Object {
        var kvs: std.ArrayList(Casl.Expr.Object.Kvs) = .empty;
        defer kvs.deinit(p.gpa); // NOTE: The kvs array doesn't live past this function. It is copied into an arena

        while (true) {
            {
                const saved_tokenizer = p.tokenizer;
                const tok = p.tokenizer.next();
                defer p.tokenizer = saved_tokenizer;

                if (tok.tag == .r_brace or tok.tag == .eof) {
                    return .{
                        .items = try p.arena.dupe(Casl.Expr.Object.Kvs, kvs.items),
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
            const value = try p.parseCasl(file_path);
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

pub const LoadError = Parser.ParseError;
pub fn load(gpa: Allocator, arena: Allocator, input: [:0]const u8, file_path: []const u8) LoadError!Casl {
    var p: Parser = .init(gpa, arena, input);

    const saved_tokenizer = p.tokenizer;
    if (p.tokenizer.next().tag == .identifier and p.tokenizer.next().tag == .equal) {
        p.tokenizer = saved_tokenizer;

        return .{ .expr = .{
            .object = try p.parseObjectBody(file_path),
        } };
    }
    p.tokenizer = saved_tokenizer;

    return p.parseCasl(file_path);
}

pub const LoadFromFileError = LoadError || Io.File.OpenError || Io.File.Reader.Error || Allocator.Error;
pub fn loadFromFile(io: Io, gpa: Allocator, arena: Allocator, file_path: []const u8) LoadFromFileError!Casl {
    const input = Io.Dir.cwd().readFileAllocOptions(io, file_path, gpa, .unlimited, .of(u8), 0) catch |err| switch (err) {
        error.StreamTooLong => unreachable,
        else => |e| return e,
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
    var arena_instance: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_instance.deinit();
    const arena = arena_instance.allocator();
    const casl = try load(std.testing.allocator, arena,
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

    try std.testing.expectEqualDeep(
        Value{ .float = 123 },
        try casl.resolvePath(arena, &.{"bla"}),
    );

    try std.testing.expectEqualDeep(
        Value{ .string = "center" },
        try casl.resolvePath(arena, &.{ "style", "link", "align" }),
    );
    try std.testing.expectEqualDeep(
        Value{ .float = 0.04 },
        try casl.resolvePath(arena, &.{ "style", "title", "font_size" }),
    );
    try std.testing.expectEqualDeep(
        Value{ .boolean = true },
        try casl.resolvePath(arena, &.{ "style", "thumbnail", "frame" }),
    );

    try std.testing.expectEqualDeep(
        Value{ .float = 0.59 },
        try casl.resolvePath(arena, &.{ "style", "title", "left" }),
    );
}
