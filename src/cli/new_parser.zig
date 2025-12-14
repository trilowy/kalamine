const std = @import("std");
const new = @import("../command/new.zig");
const Options = new.Options;
const Geometry = new.Geometry;
const CliError = @import("error.zig").CliError;

pub fn parse(args: []const []const u8) CliError!Options {
    // Must at least have one arg
    if (args.len == 0) {
        return CliError.MissingArg;
    }

    var output_file: ?[]const u8 = null;
    var geometry: ?Geometry = null;
    var altgr: ?bool = null;
    var odk: ?bool = null;

    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--altgr")) {
            if (altgr != null) {
                return CliError.DuplicatedArg;
            }
            altgr = true;
        } else if (std.mem.eql(u8, arg, "--1dk")) {
            if (odk != null) {
                return CliError.DuplicatedArg;
            }
            odk = true;
        } else if (std.mem.startsWith(u8, arg, "--geometry=")) {
            if (geometry != null) {
                return CliError.DuplicatedArg;
            }
            const geometry_value = arg["--geometry=".len..];
            if (std.mem.startsWith(u8, geometry_value, "ISO")) {
                geometry = .iso;
            } else if (std.mem.startsWith(u8, geometry_value, "ANSI")) {
                geometry = .ansi;
            } else if (std.mem.startsWith(u8, geometry_value, "ERGO")) {
                geometry = .ergo;
            } else if (std.mem.startsWith(u8, geometry_value, "ABNT")) {
                geometry = .abnt;
            } else if (std.mem.startsWith(u8, geometry_value, "JIS")) {
                geometry = .jis;
            } else if (std.mem.startsWith(u8, geometry_value, "ALT")) {
                geometry = .alt;
            } else {
                return CliError.WrongArgValue;
            }
        } else {
            if (output_file != null) {
                return CliError.DuplicatedArg;
            }
            output_file = arg;
        }
    }

    if (output_file == null) {
        return CliError.MissingArg;
    }
    if (geometry == null) {
        geometry = .iso;
    }
    if (altgr == null) {
        altgr = false;
    }
    if (odk == null) {
        odk = false;
    }

    return Options{
        .output_file = output_file.?,
        .geometry = geometry.?,
        .altgr = altgr.?,
        .odk = odk.?,
    };
}

test "parse no arg" {
    const args = [_][]const u8{};
    const result = parse(&args);
    try std.testing.expectEqual(CliError.MissingArg, result);
}

test "parse no output file" {
    const args = [_][]const u8{"--altgr"};
    const result = parse(&args);
    try std.testing.expectEqual(CliError.MissingArg, result);
}

test "parse duplicated --altgr" {
    const args = [_][]const u8{ "--altgr", "/test/file", "--altgr" };
    const result = parse(&args);
    try std.testing.expectEqual(CliError.DuplicatedArg, result);
}

test "parse duplicated --1dk" {
    const args = [_][]const u8{ "--1dk", "/test/file", "--1dk" };
    const result = parse(&args);
    try std.testing.expectEqual(CliError.DuplicatedArg, result);
}

test "parse duplicated --geometry" {
    const args = [_][]const u8{ "--geometry=ISO", "/test/file", "--geometry=ANSI" };
    const result = parse(&args);
    try std.testing.expectEqual(CliError.DuplicatedArg, result);
}

test "parse wrong --geometry value" {
    const args = [_][]const u8{ "/test/file", "--geometry=wrong" };
    const result = parse(&args);
    try std.testing.expectEqual(CliError.WrongArgValue, result);
}

test "parse output file" {
    const args = [_][]const u8{"/test/file"};
    const result = parse(&args);
    try std.testing.expectEqual(
        Options{
            .output_file = "/test/file",
            .geometry = .iso,
            .altgr = false,
            .odk = false,
        },
        result,
    );
}

test "parse file --altgr" {
    const args = [_][]const u8{ "/test/file", "--altgr" };
    const result = parse(&args);
    try std.testing.expectEqual(
        Options{
            .output_file = "/test/file",
            .geometry = .iso,
            .altgr = true,
            .odk = false,
        },
        result,
    );
}

test "parse file --1dk" {
    const args = [_][]const u8{ "/test/file", "--1dk" };
    const result = parse(&args);
    try std.testing.expectEqual(
        Options{
            .output_file = "/test/file",
            .geometry = .iso,
            .altgr = false,
            .odk = true,
        },
        result,
    );
}

test "parse file --geometry=ISO" {
    const args = [_][]const u8{ "/test/file", "--geometry=ISO" };
    const result = parse(&args);
    try std.testing.expectEqual(
        Options{
            .output_file = "/test/file",
            .geometry = .iso,
            .altgr = false,
            .odk = false,
        },
        result,
    );
}

test "parse file --geometry=ANSI" {
    const args = [_][]const u8{ "/test/file", "--geometry=ANSI" };
    const result = parse(&args);
    try std.testing.expectEqual(
        Options{
            .output_file = "/test/file",
            .geometry = .ansi,
            .altgr = false,
            .odk = false,
        },
        result,
    );
}

test "parse file --geometry=ERGO" {
    const args = [_][]const u8{ "/test/file", "--geometry=ERGO" };
    const result = parse(&args);
    try std.testing.expectEqual(
        Options{
            .output_file = "/test/file",
            .geometry = .ergo,
            .altgr = false,
            .odk = false,
        },
        result,
    );
}

test "parse file --geometry=ABNT" {
    const args = [_][]const u8{ "/test/file", "--geometry=ABNT" };
    const result = parse(&args);
    try std.testing.expectEqual(
        Options{
            .output_file = "/test/file",
            .geometry = .abnt,
            .altgr = false,
            .odk = false,
        },
        result,
    );
}

test "parse file --geometry=JIS" {
    const args = [_][]const u8{ "/test/file", "--geometry=JIS" };
    const result = parse(&args);
    try std.testing.expectEqual(
        Options{
            .output_file = "/test/file",
            .geometry = .jis,
            .altgr = false,
            .odk = false,
        },
        result,
    );
}

test "parse file --geometry=ALT" {
    const args = [_][]const u8{ "/test/file", "--geometry=ALT" };
    const result = parse(&args);
    try std.testing.expectEqual(
        Options{
            .output_file = "/test/file",
            .geometry = .alt,
            .altgr = false,
            .odk = false,
        },
        result,
    );
}

test "parse file all args" {
    const args = [_][]const u8{ "/test/file", "--altgr", "--1dk", "--geometry=ISO" };
    const result = parse(&args);
    try std.testing.expectEqual(
        Options{
            .output_file = "/test/file",
            .geometry = .iso,
            .altgr = true,
            .odk = true,
        },
        result,
    );
}

test "parse file all args in another order" {
    const args = [_][]const u8{ "--geometry=ISO", "--altgr", "/test/file", "--1dk" };
    const result = parse(&args);
    try std.testing.expectEqual(
        Options{
            .output_file = "/test/file",
            .geometry = .iso,
            .altgr = true,
            .odk = true,
        },
        result,
    );
}
