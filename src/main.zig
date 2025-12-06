//! By convention, main.zig is where your main function lives in the case that
//! you are building an executable.

const std = @import("std");
const app = @import("build.zig.zon");
const File = std.fs.File;

pub fn main() void {
    execute() catch {
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

    // Must at least have one arg
    const action = if (args.len > 1) args[1] else {
        try stderr.print("Missing arg\n", .{}); // TODO: print help
        try stderr.flush();
        return error.MissingArg;
    };

    const cmd = std.meta.stringToEnum(Command, action) orelse {
        try stderr.print("Unknown command '{s}'\n", .{action}); // TODO: print help
        try stderr.flush();
        return error.UnknownCommand;
    };

    switch (cmd) {
        .build => {
            try stdout.print("build command\n", .{});
            try stdout.flush();
        },
        .new => {
            try stdout.print("new command\n", .{});
            try stdout.flush();
        },
        .watch => {
            try stdout.print("watch command\n", .{});
            try stdout.flush();
        },
        .guide => {
            try stdout.print("guide command\n", .{});
            try stdout.flush();
        },
        .version => {
            try stdout.print("{s}\n", .{app.version});
            try stdout.flush();
        },
    }
}

const Command = enum {
    build,
    new,
    watch,
    guide,
    version,
};

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // Try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

test "fuzz example" {
    const Context = struct {
        fn testOne(context: @This(), input: []const u8) anyerror!void {
            _ = context;
            // Try passing `--fuzz` to `zig build test` and see if it manages to fail this test case!
            try std.testing.expect(!std.mem.eql(u8, "canyoufindme", input));
        }
    };
    try std.testing.fuzz(Context{}, Context.testOne, .{});
}
