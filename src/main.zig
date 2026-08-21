const std = @import("std");
const cli = @import("cli/cli.zig");
const cli_help = @import("cli/cli_help.zig");
const build = @import("command/build.zig");
const new = @import("command/new.zig");
const watch = @import("command/watch.zig");
const version = @import("command/version.zig");
const Diagnostic = @import("error_handling.zig").Diagnostic;

pub fn main(init: std.process.Init) u8 {
    const allocator = init.gpa;
    const io = init.io;

    // Parsing program args
    const args = init.minimal.args.toSlice(init.arena.allocator()) catch @panic("Out of memory");

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    var stderr_buffer: [1024]u8 = undefined;
    var stderr_writer = std.Io.File.stderr().writer(io, &stderr_buffer);
    const stderr = &stderr_writer.interface;

    execute(allocator, io, args, stdout, stderr) catch |err|
        switch (err) {
            error.ErrorReported => return 1,
            else => {
                std.log.err("{s}", .{@errorName(err)});
                return 1;
            },
        };

    return 0;
}

fn execute(
    allocator: std.mem.Allocator,
    io: std.Io,
    args: []const []const u8,
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
) !void {
    const cmd = cli.parse(args) catch |err| {
        switch (err) {
            cli.Error.InvalidArgument => {
                try stderr.writeAll(
                    \\kalamine: invalid option
                    \\Try 'kalamine --help' for more information.
                    \\
                );
            },
        }
        try stderr.flush();
        return error.ErrorReported;
    };

    switch (cmd) {
        .build => |options| {
            var diag = Diagnostic{ .allocator = allocator };
            defer diag.deinit();

            build.run(options, .{ .diagnostic = &diag }) catch |err| {
                return diag.report(stdout, err);
            };
        },
        .new => |options| {
            // No error handling because 'new' never fails
            try new.run(allocator, io, options, .{});
        },
        .watch => |options| {
            // TODO: to implement
            try stdout.writeAll("watch command not yet implemented\n");
            try stdout.flush();

            var diag = Diagnostic{ .allocator = allocator };
            defer diag.deinit();

            watch.run(options, .{ .diagnostic = &diag }) catch |err| {
                // TODO: maybe report error but do not crash when error reported
                return diag.report(stdout, err);
            };
        },
        .version => {
            try version.printTo(stdout);
        },
        .help => |options| {
            try cli_help.printTo(stdout, options);
        },
    }
}

// Run all tests of all modules added here
test {
    _ = @import("cli/ArgParser.zig");
    _ = @import("cli/cli.zig");
    _ = @import("generator/toml.zig");
    _ = @import("parser/toml.zig");
}
