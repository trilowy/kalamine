//! By convention, main.zig is where your main function lives in the case that
//! you are building an executable.

const std = @import("std");
const command = @import("command.zig");
const File = std.fs.File;
const Writer = std.Io.Writer;

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
    var stdout_writer = File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    var stderr_buffer: [1024]u8 = undefined;
    var stderr_writer = File.stderr().writer(&stderr_buffer);
    const stderr = &stderr_writer.interface;

    // Parsing program args
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const cmd = command.parse(args) catch |err| {
        switch (err) {
            error.MissingArg => {
                try stderr.print(
                    \\kalamine: missing option
                    \\Try 'kalamine --help' for more information.
                    \\
                , .{});
            },
            error.UnknownCommand,
            error.WrongArgValue,
            => {
                try stderr.print(
                    \\kalamine: invalid option
                    \\Try 'kalamine --help' for more information.
                    \\
                , .{});
            },
            error.DuplicatedArg => {
                try stderr.print("kalamine: duplicated option\n", .{});
            },
        }
        try stderr.flush();
        return err;
    };

    switch (cmd) {
        .build => {
            // TODO: to implement
            try stdout.print("build command\n", .{});
            try stdout.flush();
            try command.build();
        },
        .new => {
            // TODO: to implement
            try stdout.print("new command\n", .{});
            try stdout.flush();
            try command.new();
        },
        .watch => {
            // TODO: to implement
            try stdout.print("watch command\n", .{});
            try stdout.flush();
            try command.watch();
        },
        .version => {
            try command.version(stdout);
        },
        .help => |help_command| {
            try help_command.printTo(stdout);
        },
    }
}

// Run all tests of all modules
test {
    _ = @import("command.zig");
}
