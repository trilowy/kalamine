const std = @import("std");
const build = @import("../command/build.zig");
const Options = build.Options;
const Out = build.Out;
const CliError = @import("error.zig").CliError;

pub fn parse(args: []const []const u8) CliError!Options {
    // Must at least have one arg
    if (args.len == 0) {
        return CliError.MissingArg;
    }

    var file: ?[]const u8 = null;
    var out: ?Out = null;
    var angle_mod: ?bool = null;
    var qwerty_shortcuts: ?bool = null;

    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--angle-mod")) {
            if (angle_mod != null) {
                return CliError.DuplicatedArg;
            }
            angle_mod = true;
        } else if (std.mem.eql(u8, arg, "--qwerty-shortcuts")) {
            if (qwerty_shortcuts != null) {
                return CliError.DuplicatedArg;
            }
            qwerty_shortcuts = true;
        } else if (std.mem.startsWith(u8, arg, "--out=")) {
            if (out != null) {
                return CliError.DuplicatedArg;
            }
            out = std.meta.stringToEnum(Out, arg["--out=".len..]) orelse {
                return CliError.WrongArgValue;
            };
        } else {
            if (file != null) {
                return CliError.DuplicatedArg;
            }
            file = arg;
        }
    }

    if (file == null) {
        return CliError.MissingArg;
    }
    if (out == null) {
        out = .all;
    }
    if (angle_mod == null) {
        angle_mod = false;
    }
    if (qwerty_shortcuts == null) {
        qwerty_shortcuts = false;
    }

    return Options{
        .file = file.?,
        .out = out.?,
        .angle_mod = angle_mod.?,
        .qwerty_shortcuts = qwerty_shortcuts.?,
    };
}

test "parse no arg" {
    const args = [_][]const u8{};
    const result = parse(&args);
    try std.testing.expectEqual(CliError.MissingArg, result);
}

test "parse no file" {
    const args = [_][]const u8{"--angle-mod"};
    const result = parse(&args);
    try std.testing.expectEqual(CliError.MissingArg, result);
}

test "parse duplicated --angle-mod" {
    const args = [_][]const u8{ "--angle-mod", "/test/file", "--angle-mod" };
    const result = parse(&args);
    try std.testing.expectEqual(CliError.DuplicatedArg, result);
}

test "parse duplicated --qwerty-shortcuts" {
    const args = [_][]const u8{ "--qwerty-shortcuts", "/test/file", "--qwerty-shortcuts" };
    const result = parse(&args);
    try std.testing.expectEqual(CliError.DuplicatedArg, result);
}

test "parse duplicated --out" {
    const args = [_][]const u8{ "--out=all", "/test/file", "--out=keylayout" };
    const result = parse(&args);
    try std.testing.expectEqual(CliError.DuplicatedArg, result);
}

test "parse wrong --out value" {
    const args = [_][]const u8{ "/test/file", "--out=wrong" };
    const result = parse(&args);
    try std.testing.expectEqual(CliError.WrongArgValue, result);
}

test "parse file" {
    const args = [_][]const u8{"/test/file"};
    const result = parse(&args);
    try std.testing.expectEqual(
        Options{
            .file = "/test/file",
            .out = .all,
            .angle_mod = false,
            .qwerty_shortcuts = false,
        },
        result,
    );
}

test "parse file --angle-mod" {
    const args = [_][]const u8{ "/test/file", "--angle-mod" };
    const result = parse(&args);
    try std.testing.expectEqual(
        Options{
            .file = "/test/file",
            .out = .all,
            .angle_mod = true,
            .qwerty_shortcuts = false,
        },
        result,
    );
}

test "parse file --qwerty-shortcuts" {
    const args = [_][]const u8{ "/test/file", "--qwerty-shortcuts" };
    const result = parse(&args);
    try std.testing.expectEqual(
        Options{
            .file = "/test/file",
            .out = .all,
            .angle_mod = false,
            .qwerty_shortcuts = true,
        },
        result,
    );
}

test "parse file --out=keylayout" {
    const args = [_][]const u8{ "/test/file", "--out=keylayout" };
    const result = parse(&args);
    try std.testing.expectEqual(
        Options{
            .file = "/test/file",
            .out = .keylayout,
            .angle_mod = false,
            .qwerty_shortcuts = false,
        },
        result,
    );
}

test "parse file --out=klc" {
    const args = [_][]const u8{ "/test/file", "--out=klc" };
    const result = parse(&args);
    try std.testing.expectEqual(
        Options{
            .file = "/test/file",
            .out = .klc,
            .angle_mod = false,
            .qwerty_shortcuts = false,
        },
        result,
    );
}

test "parse file --out=xkb_keymap" {
    const args = [_][]const u8{ "/test/file", "--out=xkb_keymap" };
    const result = parse(&args);
    try std.testing.expectEqual(
        Options{
            .file = "/test/file",
            .out = .xkb_keymap,
            .angle_mod = false,
            .qwerty_shortcuts = false,
        },
        result,
    );
}

test "parse file --out=xkb_symbols" {
    const args = [_][]const u8{ "/test/file", "--out=xkb_symbols" };
    const result = parse(&args);
    try std.testing.expectEqual(
        Options{
            .file = "/test/file",
            .out = .xkb_symbols,
            .angle_mod = false,
            .qwerty_shortcuts = false,
        },
        result,
    );
}

test "parse file --out=svg" {
    const args = [_][]const u8{ "/test/file", "--out=svg" };
    const result = parse(&args);
    try std.testing.expectEqual(
        Options{
            .file = "/test/file",
            .out = .svg,
            .angle_mod = false,
            .qwerty_shortcuts = false,
        },
        result,
    );
}

test "parse file all args" {
    const args = [_][]const u8{ "/test/file", "--angle-mod", "--qwerty-shortcuts", "--out=all" };
    const result = parse(&args);
    try std.testing.expectEqual(
        Options{
            .file = "/test/file",
            .out = .all,
            .angle_mod = true,
            .qwerty_shortcuts = true,
        },
        result,
    );
}

test "parse file all args in another order" {
    const args = [_][]const u8{ "--out=all", "--angle-mod", "/test/file", "--qwerty-shortcuts" };
    const result = parse(&args);
    try std.testing.expectEqual(
        Options{
            .file = "/test/file",
            .out = .all,
            .angle_mod = true,
            .qwerty_shortcuts = true,
        },
        result,
    );
}
