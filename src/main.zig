//! By convention, main.zig is where your main function lives in the case that
//! you are building an executable.

pub fn main() !void {
    // a general purpose allocator
    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    const allocator = debug_allocator.allocator();
    defer _ = debug_allocator.deinit();

    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();

    // parsing program args
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // must at least have one arg
    const action = if (args.len > 1) args[1] else {
        try stderr.print("missing arg", .{}); // TODO: print help
        return error.MissingArg;
    };

    const cmd = std.meta.stringToEnum(Command, action) orelse {
        try stderr.print("unknown command {s}\n", .{action}); // TODO: print help
        return error.UnknownCommand;
    };

    switch (cmd) {
        .build => {
            try stdout.print("build command\n", .{});
        },
        .new => {
            try stdout.print("new command\n", .{});
        },
        .watch => {
            try stdout.print("watch command\n", .{});
        },
        .guide => {
            try stdout.print("guide command\n", .{});
        },
        .version => {
            try stdout.print("kalamine {s}\n", .{app.version});
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

const std = @import("std");
const app = @import("build.zig.zon");
