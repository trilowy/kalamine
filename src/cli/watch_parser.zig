const std = @import("std");
const Options = @import("../command/watch.zig").Options;
const CliError = @import("error.zig").CliError;

pub fn parse(args: []const []const u8) CliError!Options {
    // Must at least have one arg
    if (args.len == 0) {
        return CliError.MissingArg;
    }

    var file: ?[]const u8 = null;
    var angle_mod: ?bool = null;

    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--angle-mod")) {
            if (angle_mod != null) {
                return CliError.DuplicatedArg;
            }
            angle_mod = true;
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
    if (angle_mod == null) {
        angle_mod = false;
    }

    return Options{
        .file = file.?,
        .angle_mod = angle_mod.?,
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

test "parse file" {
    const args = [_][]const u8{"/test/file"};
    const result = parse(&args);
    try std.testing.expectEqual(
        Options{
            .file = "/test/file",
            .angle_mod = false,
        },
        result,
    );
}

test "parse file all args" {
    const args = [_][]const u8{ "/test/file", "--angle-mod" };
    const result = parse(&args);
    try std.testing.expectEqual(
        Options{
            .file = "/test/file",
            .angle_mod = true,
        },
        result,
    );
}

test "parse file all args in another order" {
    const args = [_][]const u8{ "--angle-mod", "/test/file" };
    const result = parse(&args);
    try std.testing.expectEqual(
        Options{
            .file = "/test/file",
            .angle_mod = true,
        },
        result,
    );
}
