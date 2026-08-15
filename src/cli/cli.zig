//! Parser for CLI arguments

const std = @import("std");
const ArgParser = @import("ArgParser.zig");
const Command = @import("../command/command.zig").Command;
const build = @import("../command/build.zig");
const new = @import("../command/new.zig");
const watch = @import("../command/watch.zig");
const Geometry = @import("../layout.zig").Geometry;

/// Parse program arguments
pub fn parse(args: []const []const u8) Error!Command {
    var arg_parser = ArgParser{ .args = args[1..] };

    if (arg_parser.next()) {
        if (arg_parser.flag(&.{"build"})) {
            return parseBuild(&arg_parser);
        }
        if (arg_parser.flag(&.{"new"})) {
            return parseNew(&arg_parser);
        }
        if (arg_parser.flag(&.{"watch"})) {
            return parseWatch(&arg_parser);
        }
        if (arg_parser.flag(&.{"--version"})) {
            return .version;
        }
        if (arg_parser.flag(&.{ "-h", "--help" })) {
            return .{ .help = .global };
        }
    }

    return Error.InvalidArgument;
}

fn parseBuild(arg_parser: *ArgParser) Error!Command {
    var file: ?[]const u8 = null;
    var out: build.Out = .all;
    var angle_mod = false;
    var qwerty_shortcuts = false;

    while (arg_parser.next()) {
        if (arg_parser.flag(&.{ "-h", "--help" })) {
            return .{ .help = .build };
        }
        if (arg_parser.flag(&.{"--angle-mod"})) {
            angle_mod = true;
        }
        if (arg_parser.flag(&.{"--qwerty-shortcuts"})) {
            qwerty_shortcuts = true;
        }
        if (arg_parser.option(&.{"--out"})) |out_value| {
            out = std.meta.stringToEnum(build.Out, out_value) orelse {
                return Error.InvalidArgument;
            };
        }
        if (arg_parser.positional()) |file_value| {
            file = file_value;
        }
    }

    if (file == null) {
        return Error.InvalidArgument;
    }

    return .{ .build = build.Options{
        .file = file.?,
        .out = out,
        .angle_mod = angle_mod,
        .qwerty_shortcuts = qwerty_shortcuts,
    } };
}

fn parseNew(arg_parser: *ArgParser) Error!Command {
    var output_file: ?[]const u8 = null;
    var geometry: Geometry = .ISO;
    var altgr = false;
    var odk = false;

    while (arg_parser.next()) {
        if (arg_parser.flag(&.{ "-h", "--help" })) {
            return .{ .help = .new };
        }
        if (arg_parser.flag(&.{"--altgr"})) {
            altgr = true;
        }
        if (arg_parser.flag(&.{"--1dk"})) {
            odk = true;
        }
        if (arg_parser.option(&.{"--geometry"})) |geometry_value| {
            geometry = std.meta.stringToEnum(Geometry, geometry_value) orelse {
                return Error.InvalidArgument;
            };
        }
        if (arg_parser.positional()) |output_file_value| {
            output_file = output_file_value;
        }
    }

    if (output_file == null) {
        return Error.InvalidArgument;
    }

    return .{ .new = new.Options{
        .output_file = output_file.?,
        .geometry = geometry,
        .altgr = altgr,
        .odk = odk,
    } };
}

fn parseWatch(arg_parser: *ArgParser) Error!Command {
    var file: ?[]const u8 = null;
    var angle_mod = false;

    while (arg_parser.next()) {
        if (arg_parser.flag(&.{ "-h", "--help" })) {
            return .{ .help = .watch };
        }
        if (arg_parser.flag(&.{"--angle-mod"})) {
            angle_mod = true;
        }
        if (arg_parser.positional()) |file_value| {
            file = file_value;
        }
    }

    if (file == null) {
        return Error.InvalidArgument;
    }

    return .{ .watch = watch.Options{
        .file = file.?,
        .angle_mod = angle_mod,
    } };
}

pub const Error = error{
    InvalidArgument,
};

test "parse missing arg" {
    const args = [_][]const u8{"kalamine"};
    try std.testing.expectEqual(Error.InvalidArgument, parse(&args));
}

test "parse build -h" {
    const args = [_][]const u8{ "kalamine", "build", "-h" };
    try std.testing.expectEqual(Command{ .help = .build }, parse(&args));
}

test "parse build --help" {
    const args = [_][]const u8{ "kalamine", "build", "--help" };
    try std.testing.expectEqual(Command{ .help = .build }, parse(&args));
}

test "parse build no arg" {
    const args = [_][]const u8{ "kalamine", "build" };
    try std.testing.expectEqual(Error.InvalidArgument, parse(&args));
}

test "parse build no file" {
    const args = [_][]const u8{ "kalamine", "build", "--angle-mod" };
    try std.testing.expectEqual(Error.InvalidArgument, parse(&args));
}

test "parse build wrong --out value" {
    const args = [_][]const u8{ "kalamine", "build", "/test/file", "--out=wrong" };
    try std.testing.expectEqual(Error.InvalidArgument, parse(&args));
}

test "parse build file" {
    const args = [_][]const u8{ "kalamine", "build", "/test/file" };
    try std.testing.expectEqual(
        Command{
            .build = build.Options{
                .file = "/test/file",
                .out = .all,
                .angle_mod = false,
                .qwerty_shortcuts = false,
            },
        },
        parse(&args),
    );
}

test "parse build file --angle-mod" {
    const args = [_][]const u8{ "kalamine", "build", "/test/file", "--angle-mod" };
    try std.testing.expectEqual(
        Command{
            .build = build.Options{
                .file = "/test/file",
                .out = .all,
                .angle_mod = true,
                .qwerty_shortcuts = false,
            },
        },
        parse(&args),
    );
}

test "parse build file --qwerty-shortcuts" {
    const args = [_][]const u8{ "kalamine", "build", "/test/file", "--qwerty-shortcuts" };
    try std.testing.expectEqual(
        Command{
            .build = build.Options{
                .file = "/test/file",
                .out = .all,
                .angle_mod = false,
                .qwerty_shortcuts = true,
            },
        },
        parse(&args),
    );
}

test "parse build file --out=keylayout" {
    const args = [_][]const u8{ "kalamine", "build", "/test/file", "--out=keylayout" };
    try std.testing.expectEqual(
        Command{
            .build = build.Options{
                .file = "/test/file",
                .out = .keylayout,
                .angle_mod = false,
                .qwerty_shortcuts = false,
            },
        },
        parse(&args),
    );
}

test "parse build file --out=klc" {
    const args = [_][]const u8{ "kalamine", "build", "/test/file", "--out=klc" };
    try std.testing.expectEqual(
        Command{
            .build = build.Options{
                .file = "/test/file",
                .out = .klc,
                .angle_mod = false,
                .qwerty_shortcuts = false,
            },
        },
        parse(&args),
    );
}

test "parse build file --out=xkb_keymap" {
    const args = [_][]const u8{ "kalamine", "build", "/test/file", "--out=xkb_keymap" };
    try std.testing.expectEqual(
        Command{
            .build = build.Options{
                .file = "/test/file",
                .out = .xkb_keymap,
                .angle_mod = false,
                .qwerty_shortcuts = false,
            },
        },
        parse(&args),
    );
}

test "parse build file --out=xkb_symbols" {
    const args = [_][]const u8{ "kalamine", "build", "/test/file", "--out=xkb_symbols" };
    try std.testing.expectEqual(
        Command{
            .build = build.Options{
                .file = "/test/file",
                .out = .xkb_symbols,
                .angle_mod = false,
                .qwerty_shortcuts = false,
            },
        },
        parse(&args),
    );
}

test "parse build file --out=svg" {
    const args = [_][]const u8{ "kalamine", "build", "/test/file", "--out=svg" };
    try std.testing.expectEqual(
        Command{
            .build = build.Options{
                .file = "/test/file",
                .out = .svg,
                .angle_mod = false,
                .qwerty_shortcuts = false,
            },
        },
        parse(&args),
    );
}

test "parse build file all args" {
    const args = [_][]const u8{ "kalamine", "build", "/test/file", "--angle-mod", "--qwerty-shortcuts", "--out=all" };
    try std.testing.expectEqual(
        Command{
            .build = build.Options{
                .file = "/test/file",
                .out = .all,
                .angle_mod = true,
                .qwerty_shortcuts = true,
            },
        },
        parse(&args),
    );
}

test "parse build file all args in another order" {
    const args = [_][]const u8{ "kalamine", "build", "--out=all", "--angle-mod", "/test/file", "--qwerty-shortcuts" };
    try std.testing.expectEqual(
        Command{
            .build = build.Options{
                .file = "/test/file",
                .out = .all,
                .angle_mod = true,
                .qwerty_shortcuts = true,
            },
        },
        parse(&args),
    );
}

test "parse new -h" {
    const args = [_][]const u8{ "kalamine", "new", "-h" };
    try std.testing.expectEqual(Command{ .help = .new }, parse(&args));
}

test "parse new --help" {
    const args = [_][]const u8{ "kalamine", "new", "--help" };
    try std.testing.expectEqual(Command{ .help = .new }, parse(&args));
}

test "parse new no arg" {
    const args = [_][]const u8{ "kalamine", "new" };
    try std.testing.expectEqual(Error.InvalidArgument, parse(&args));
}

test "parse new no output file" {
    const args = [_][]const u8{ "kalamine", "new", "--altgr" };
    try std.testing.expectEqual(Error.InvalidArgument, parse(&args));
}

test "parse new wrong --geometry value" {
    const args = [_][]const u8{ "kalamine", "new", "/test/file", "--geometry=wrong" };
    try std.testing.expectEqual(Error.InvalidArgument, parse(&args));
}

test "parse new output file" {
    const args = [_][]const u8{ "kalamine", "new", "/test/file" };
    try std.testing.expectEqual(
        Command{
            .new = new.Options{
                .output_file = "/test/file",
                .geometry = .ISO,
                .altgr = false,
                .odk = false,
            },
        },
        parse(&args),
    );
}

test "parse new file --altgr" {
    const args = [_][]const u8{ "kalamine", "new", "/test/file", "--altgr" };
    try std.testing.expectEqual(
        Command{
            .new = new.Options{
                .output_file = "/test/file",
                .geometry = .ISO,
                .altgr = true,
                .odk = false,
            },
        },
        parse(&args),
    );
}

test "parse new file --1dk" {
    const args = [_][]const u8{ "kalamine", "new", "/test/file", "--1dk" };
    try std.testing.expectEqual(
        Command{
            .new = new.Options{
                .output_file = "/test/file",
                .geometry = .ISO,
                .altgr = false,
                .odk = true,
            },
        },
        parse(&args),
    );
}

test "parse new file --geometry=ISO" {
    const args = [_][]const u8{ "kalamine", "new", "/test/file", "--geometry=ISO" };
    try std.testing.expectEqual(
        Command{
            .new = new.Options{
                .output_file = "/test/file",
                .geometry = .ISO,
                .altgr = false,
                .odk = false,
            },
        },
        parse(&args),
    );
}

test "parse new file --geometry=ANSI" {
    const args = [_][]const u8{ "kalamine", "new", "/test/file", "--geometry=ANSI" };
    try std.testing.expectEqual(
        Command{
            .new = new.Options{
                .output_file = "/test/file",
                .geometry = .ANSI,
                .altgr = false,
                .odk = false,
            },
        },
        parse(&args),
    );
}

test "parse new file --geometry=ERGO" {
    const args = [_][]const u8{ "kalamine", "new", "/test/file", "--geometry=ERGO" };
    try std.testing.expectEqual(
        Command{
            .new = new.Options{
                .output_file = "/test/file",
                .geometry = .ERGO,
                .altgr = false,
                .odk = false,
            },
        },
        parse(&args),
    );
}

test "parse new file --geometry=ABNT" {
    const args = [_][]const u8{ "kalamine", "new", "/test/file", "--geometry=ABNT" };
    try std.testing.expectEqual(
        Command{
            .new = new.Options{
                .output_file = "/test/file",
                .geometry = .ABNT,
                .altgr = false,
                .odk = false,
            },
        },
        parse(&args),
    );
}

test "parse new file --geometry=JIS" {
    const args = [_][]const u8{ "kalamine", "new", "/test/file", "--geometry=JIS" };
    try std.testing.expectEqual(
        Command{
            .new = new.Options{
                .output_file = "/test/file",
                .geometry = .JIS,
                .altgr = false,
                .odk = false,
            },
        },
        parse(&args),
    );
}

test "parse new file --geometry=ALT" {
    const args = [_][]const u8{ "kalamine", "new", "/test/file", "--geometry=ALT" };
    try std.testing.expectEqual(
        Command{
            .new = new.Options{
                .output_file = "/test/file",
                .geometry = .ALT,
                .altgr = false,
                .odk = false,
            },
        },
        parse(&args),
    );
}

test "parse new file all args" {
    const args = [_][]const u8{ "kalamine", "new", "/test/file", "--altgr", "--1dk", "--geometry=ISO" };
    try std.testing.expectEqual(
        Command{
            .new = new.Options{
                .output_file = "/test/file",
                .geometry = .ISO,
                .altgr = true,
                .odk = true,
            },
        },
        parse(&args),
    );
}

test "parse new file all args in another order" {
    const args = [_][]const u8{ "kalamine", "new", "--geometry=ISO", "--altgr", "/test/file", "--1dk" };
    try std.testing.expectEqual(
        Command{
            .new = new.Options{
                .output_file = "/test/file",
                .geometry = .ISO,
                .altgr = true,
                .odk = true,
            },
        },
        parse(&args),
    );
}
test "parse new all args" {
    const args = [_][]const u8{ "kalamine", "new", "/test/file", "--altgr", "--1dk", "--geometry=ISO" };
    try std.testing.expectEqual(
        Command{
            .new = new.Options{
                .output_file = "/test/file",
                .geometry = .ISO,
                .altgr = true,
                .odk = true,
            },
        },
        parse(&args),
    );
}

test "parse watch -h" {
    const args = [_][]const u8{ "kalamine", "watch", "-h" };
    try std.testing.expectEqual(Command{ .help = .watch }, parse(&args));
}

test "parse watch --help" {
    const args = [_][]const u8{ "kalamine", "watch", "--help" };
    try std.testing.expectEqual(Command{ .help = .watch }, parse(&args));
}

test "parse watch no arg" {
    const args = [_][]const u8{ "kalamine", "watch" };
    try std.testing.expectEqual(Error.InvalidArgument, parse(&args));
}

test "parse watch no file" {
    const args = [_][]const u8{ "kalamine", "watch", "--angle-mod" };
    try std.testing.expectEqual(Error.InvalidArgument, parse(&args));
}

test "parse watch file" {
    const args = [_][]const u8{ "kalamine", "watch", "/test/file" };
    try std.testing.expectEqual(
        Command{
            .watch = watch.Options{
                .file = "/test/file",
                .angle_mod = false,
            },
        },
        parse(&args),
    );
}

test "parse watch file all args" {
    const args = [_][]const u8{ "kalamine", "watch", "/test/file", "--angle-mod" };
    try std.testing.expectEqual(
        Command{
            .watch = watch.Options{
                .file = "/test/file",
                .angle_mod = true,
            },
        },
        parse(&args),
    );
}

test "parse watch file all args in another order" {
    const args = [_][]const u8{ "kalamine", "watch", "--angle-mod", "/test/file" };
    try std.testing.expectEqual(
        Command{
            .watch = watch.Options{
                .file = "/test/file",
                .angle_mod = true,
            },
        },
        parse(&args),
    );
}

test "parse --version" {
    const args = [_][]const u8{ "kalamine", "--version" };
    try std.testing.expectEqual(.version, parse(&args));
}

test "parse --help" {
    const args = [_][]const u8{ "kalamine", "--help" };
    try std.testing.expectEqual(Command{ .help = .global }, parse(&args));
}

test "parse -h" {
    const args = [_][]const u8{ "kalamine", "-h" };
    try std.testing.expectEqual(Command{ .help = .global }, parse(&args));
}

test "parse unknown" {
    const args = [_][]const u8{ "kalamine", "unknown" };
    try std.testing.expectEqual(Error.InvalidArgument, parse(&args));
}
