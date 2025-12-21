const std = @import("std");
const ArgParser = @import("cli/ArgParser.zig");
const cli = @import("cli/cli.zig");
const cli_help = @import("cli/cli_help.zig");
const build = @import("command/build.zig");
const new = @import("command/new.zig");
const watch = @import("command/watch.zig");
const version = @import("command/version.zig");
const CliError = @import("cli/error.zig").CliError;

pub fn main() u8 {
    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    const allocator = debug_allocator.allocator();
    defer _ = debug_allocator.deinit();

    // Parsing program args
    const args = std.process.argsAlloc(allocator) catch @panic("Out of memory");
    defer std.process.argsFree(allocator, args);

    var stdout_buffer: [std.heap.page_size_min]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    var stderr_buffer: [std.heap.page_size_min]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buffer);
    const stderr = &stderr_writer.interface;

    execute(allocator, args, stdout, stderr) catch |err|
        switch (err) {
            error.ErrorReported => return 1,
            else => {
                std.log.err("{s}", .{@errorName(err)}); // TODO: see what it does, stderr?
                return 1;
            },
        };

    return 0;
}

fn execute(
    allocator: std.mem.Allocator,
    args: []const []const u8,
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
) !void {
    var arg_parser = ArgParser{ .args = args };

    // TODO: https://github.com/Hejsil/dipm/blob/4b24131e2b010ef8577fb650ca39d2305e6b3b4e/src/main.zig#L73
    const cmd = cli.parse(args) catch |err| {
        switch (err) {
            CliError.MissingArg => {
                try stderr.writeAll(
                    \\kalamine: missing option
                    \\Try 'kalamine --help' for more information.
                    \\
                );
            },
            CliError.UnknownCommand,
            CliError.WrongArgValue,
            => {
                try stderr.writeAll(
                    \\kalamine: invalid option
                    \\Try 'kalamine --help' for more information.
                    \\
                );
            },
            CliError.DuplicatedArg => {
                try stderr.writeAll("kalamine: duplicated option\n");
            },
        }
        try stderr.flush();
        return err;
    };

    switch (cmd) {
        .build => |options| {
            // TODO: to implement
            try stdout.writeAll("build command not yet implemented\n");
            try stdout.flush();
            try build.run(options); // TODO: handle error
        },
        .new => |options| {
            // TODO: to implement
            try stdout.writeAll("new command not yet implemented\n");
            try stdout.flush();
            try new.run(options); // TODO: handle error
        },
        .watch => |options| {
            // TODO: to implement
            try stdout.writeAll("watch command not yet implemented\n");
            try stdout.flush();
            try watch.run(options); // TODO: handle error
        },
        .version => {
            try version.printTo(stdout);
        },
        .help => |options| {
            try cli_help.printTo(stdout, options);
        },
    }
}

const main_usage =
    \\Usage: kalamine [command] [options]
    \\
    \\Commands:
    \\  build <file> [options]  Convert TOML/YAML descriptions into OS-specific keyboard drivers.
    \\  new <file> [options]    Create a new TOML layout description.
    \\  watch <file> [options]  Watch a layout description file and display it in a web browser.
    \\
    \\Options:
    \\  -h --help               Show this screen.
    \\  --version               Show version.
    \\
;

// Run all tests of all modules
test {
    _ = @import("cli/cli.zig");
    _ = @import("cli/build_parser.zig");
    _ = @import("cli/new_parser.zig");
    _ = @import("cli/watch_parser.zig");
}
