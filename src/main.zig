const std = @import("std");
const cli = @import("cli/cli.zig");
const cli_help = @import("cli/cli_help.zig");
const build = @import("command/build.zig");
const new = @import("command/new.zig");
const watch = @import("command/watch.zig");
const version = @import("command/version.zig");
const Diagnostic = @import("error_handling.zig").Diagnostic;

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
                std.log.err("{s}", .{@errorName(err)});
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
            // TODO: to implement
            try stdout.writeAll("build command not yet implemented\n");
            try stdout.flush();
            try build.run(options); // TODO: handle error
        },
        .new => |options| {
            // TODO: to implement
            var diag = Diagnostic{};

            try new.run(allocator, options, .{ .diagnostic = &diag }) catch |err| {
                return diag.report(stdout, err);
                // TODO: no error for new layout but report error at higher level for build
            }; // TODO: handle error
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

// Run all tests of all modules added here
test {
    _ = @import("cli/cli.zig");
    _ = @import("cli/ArgParser.zig");
    _ = @import("layout/parser.zig");
}
