//! By convention, main.zig is where your main function lives in the case that
//! you are building an executable.

const std = @import("std");
const cli = @import("cli/cli.zig");
const cli_help = @import("cli/cli_help.zig");
const build = @import("command/build.zig");
const new = @import("command/new.zig");
const watch = @import("command/watch.zig");
const version = @import("command/version.zig");
const CliError = @import("cli/error.zig").CliError;

pub fn main() void {
    execute() catch {
        // TODO: unknown error, message?
        std.process.exit(1);
    };
}

fn execute() !void {
    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    const allocator = debug_allocator.allocator();
    defer _ = debug_allocator.deinit();

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    var stderr_buffer: [1024]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buffer);
    const stderr = &stderr_writer.interface;

    // Parsing program args
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const cmd = cli.parse(args) catch |err| {
        switch (err) {
            CliError.MissingArg => {
                try stderr.print(
                    \\kalamine: missing option
                    \\Try 'kalamine --help' for more information.
                    \\
                , .{});
            },
            CliError.UnknownCommand,
            CliError.WrongArgValue,
            => {
                try stderr.print(
                    \\kalamine: invalid option
                    \\Try 'kalamine --help' for more information.
                    \\
                , .{});
            },
            CliError.DuplicatedArg => {
                try stderr.print("kalamine: duplicated option\n", .{});
            },
        }
        try stderr.flush();
        return err;
    };

    switch (cmd) {
        .build => |options| {
            // TODO: to implement
            try stdout.print("build command not yet implemented\n", .{});
            try stdout.flush();
            try build.run(options);
        },
        .new => {
            // TODO: to implement
            try stdout.print("new command not yet implemented\n", .{});
            try stdout.flush();
            try new.run();
        },
        .watch => {
            // TODO: to implement
            try stdout.print("watch command not yet implemented\n", .{});
            try stdout.flush();
            try watch.run();
        },
        .version => {
            try version.printTo(stdout);
        },
        .help => |options| {
            try cli_help.printTo(stdout, options);
        },
    }
}

// Run all tests of all modules
test {
    _ = @import("cli/cli.zig");
    _ = @import("cli/build_parser.zig");
    _ = @import("cli/new_parser.zig");
}
