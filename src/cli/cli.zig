const std = @import("std");
const build_parser = @import("build_parser.zig");
const new_parser = @import("new_parser.zig");
const watch_parser = @import("watch_parser.zig");
const build = @import("../command/build.zig");
const new = @import("../command/new.zig");
const watch = @import("../command/watch.zig");
const Command = @import("../command/command.zig").Command;
const CliError = @import("error.zig").CliError;

pub fn parse(args: []const []const u8) CliError!Command {
    // Must at least have one arg for the command
    const action = if (args.len > 1) args[1] else {
        return CliError.MissingArg;
    };

    const options = args[2..];

    if (std.mem.eql(u8, action, "build")) {
        if (isHelp(options)) {
            return .{ .help = .build };
        }
        const build_options = try build_parser.parse(options);
        return .{ .build = build_options };
    } else if (std.mem.eql(u8, action, "new")) {
        if (isHelp(options)) {
            return .{ .help = .new };
        }
        const new_options = try new_parser.parse(options);
        return .{ .new = new_options };
    } else if (std.mem.eql(u8, action, "watch")) {
        if (isHelp(options)) {
            return .{ .help = .watch };
        }
        const watch_options = try watch_parser.parse(options);
        return .{ .watch = watch_options };
    } else if (std.mem.eql(u8, action, "--version")) {
        return .version;
    } else if (std.mem.eql(u8, action, "--help") or std.mem.eql(u8, action, "-h")) {
        return .{ .help = .global };
    } else {
        return CliError.UnknownCommand;
    }
}

fn isHelp(args: []const []const u8) bool {
    return args.len == 1 and (std.mem.eql(u8, args[0], "-h") or std.mem.eql(u8, args[0], "--help"));
}

test "parse missing arg" {
    const args = [_][]const u8{"kalamine"};
    const result = parse(&args);
    try std.testing.expectEqual(CliError.MissingArg, result);
}

test "parse build all args" {
    const args = [_][]const u8{ "kalamine", "build", "/test/file", "--angle-mod", "--qwerty-shortcuts", "--out=all" };
    const result = parse(&args);
    try std.testing.expectEqual(
        Command{
            .build = build.Options{
                .file = "/test/file",
                .out = .all,
                .angle_mod = true,
                .qwerty_shortcuts = true,
            },
        },
        result,
    );
}

test "parse build -h" {
    const args = [_][]const u8{ "kalamine", "build", "-h" };
    const result = parse(&args);
    try std.testing.expectEqual(Command{ .help = .build }, result);
}

test "parse build --help" {
    const args = [_][]const u8{ "kalamine", "build", "--help" };
    const result = parse(&args);
    try std.testing.expectEqual(Command{ .help = .build }, result);
}

test "parse build -h with to many arg" {
    const args = [_][]const u8{ "kalamine", "build", "-h", "wrong" };
    const result = parse(&args);
    try std.testing.expectEqual(CliError.DuplicatedArg, result);
}

test "parse build --help with to many arg" {
    const args = [_][]const u8{ "kalamine", "build", "--help", "wrong" };
    const result = parse(&args);
    try std.testing.expectEqual(CliError.DuplicatedArg, result);
}

test "parse new all args" {
    const args = [_][]const u8{ "kalamine", "new", "/test/file", "--altgr", "--1dk", "--geometry=ISO" };
    const result = parse(&args);
    try std.testing.expectEqual(
        Command{
            .new = new.Options{
                .output_file = "/test/file",
                .geometry = .iso,
                .altgr = true,
                .odk = true,
            },
        },
        result,
    );
}

test "parse new -h" {
    const args = [_][]const u8{ "kalamine", "new", "-h" };
    const result = parse(&args);
    try std.testing.expectEqual(Command{ .help = .new }, result);
}

test "parse new --help" {
    const args = [_][]const u8{ "kalamine", "new", "--help" };
    const result = parse(&args);
    try std.testing.expectEqual(Command{ .help = .new }, result);
}

test "parse new -h with to many arg" {
    const args = [_][]const u8{ "kalamine", "new", "-h", "wrong" };
    const result = parse(&args);
    try std.testing.expectEqual(CliError.DuplicatedArg, result);
}

test "parse new --help with to many arg" {
    const args = [_][]const u8{ "kalamine", "new", "--help", "wrong" };
    const result = parse(&args);
    try std.testing.expectEqual(CliError.DuplicatedArg, result);
}

test "parse watch all args" {
    const args = [_][]const u8{ "kalamine", "watch", "/test/file", "--angle-mod" };
    const result = parse(&args);
    try std.testing.expectEqual(
        Command{
            .watch = watch.Options{
                .file = "/test/file",
                .angle_mod = true,
            },
        },
        result,
    );
}

test "parse watch -h" {
    const args = [_][]const u8{ "kalamine", "watch", "-h" };
    const result = parse(&args);
    try std.testing.expectEqual(Command{ .help = .watch }, result);
}

test "parse watch --help" {
    const args = [_][]const u8{ "kalamine", "watch", "--help" };
    const result = parse(&args);
    try std.testing.expectEqual(Command{ .help = .watch }, result);
}

test "parse watch -h with to many arg" {
    const args = [_][]const u8{ "kalamine", "watch", "-h", "wrong" };
    const result = parse(&args);
    try std.testing.expectEqual(CliError.DuplicatedArg, result);
}

test "parse watch --help with to many arg" {
    const args = [_][]const u8{ "kalamine", "watch", "--help", "wrong" };
    const result = parse(&args);
    try std.testing.expectEqual(CliError.DuplicatedArg, result);
}

test "parse --version" {
    const args = [_][]const u8{ "kalamine", "--version" };
    const result = parse(&args);
    try std.testing.expectEqual(.version, result);
}

test "parse --help" {
    const args = [_][]const u8{ "kalamine", "--help" };
    const result = parse(&args);
    try std.testing.expectEqual(Command{ .help = .global }, result);
}

test "parse -h" {
    const args = [_][]const u8{ "kalamine", "-h" };
    const result = parse(&args);
    try std.testing.expectEqual(Command{ .help = .global }, result);
}

test "parse unknown" {
    const args = [_][]const u8{ "kalamine", "unknown" };
    const result = parse(&args);
    try std.testing.expectEqual(CliError.UnknownCommand, result);
}
