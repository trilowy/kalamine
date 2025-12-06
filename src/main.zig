//! By convention, main.zig is where your main function lives in the case that
//! you are building an executable.

const std = @import("std");
const command = @import("command.zig");
const File = std.fs.File;
const Writer = std.Io.Writer;

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

    if (std.mem.eql(u8, action, "build")) {
        // TODO: Convert TOML/YAML descriptions into OS-specific keyboard drivers.
        // @click.argument(
        //     "layout_descriptors",
        //     nargs=-1,
        //     type=click.Path(exists=True, dir_okay=False, path_type=Path),
        // )
        // @click.option(
        //     "--out",
        //     default="all",
        //     type=click.Path(),
        //     help="Keyboard drivers to generate.",
        // )
        // @click.option(
        //     "--angle-mod/--no-angle-mod",
        //     default=False,
        //     help="Apply Angle-Mod (which is a [ZXCVB] permutation with the LSGT key (a.k.a. ISO key))",
        // )
        // @click.option(
        //     "--qwerty-shortcuts",
        //     default=False,
        //     is_flag=True,
        //     help="Keep shortcuts at their qwerty location",
        // )
        try stdout.print("build command\n", .{});
        try stdout.flush();
    } else if (std.mem.eql(u8, action, "new")) {
        // TODO: Provide geometry choices
        // TODO: Create a new TOML layout description.
        // @click.argument("output_file", nargs=1, type=click.Path(exists=False, path_type=Path))
        // @click.option("--geometry", default="ISO", help="Specify keyboard geometry.")
        // @click.option("--altgr/--no-altgr", default=False, help="Set an AltGr layer.")
        // @click.option("--1dk/--no-1dk", "odk", default=False, help="Set a custom dead key.")
        try stdout.print("new command\n", .{});
        try stdout.flush();
    } else if (std.mem.eql(u8, action, "watch")) {
        // TODO: Watch a layout description file and display it in a web browser.
        // @click.argument("filepath", nargs=1, type=click.Path(exists=True, path_type=Path))
        // @click.option(
        //     "--angle-mod/--no-angle-mod",
        //     default=False,
        //     help="Apply Angle-Mod (which is a [ZXCVB] permutation with the LSGT key (a.k.a. ISO key))",
        // )
        try stdout.print("watch command\n", .{});
        try stdout.flush();
    } else if (std.mem.eql(u8, action, "guide")) {
        // TODO: Show user guide and exit.
        // TODO: Kalamine, a keyboard layout maker
        try stdout.print("guide command\n", .{});
        try stdout.flush();
    } else if (std.mem.eql(u8, action, "--version")) {
        try command.version(stdout);
    } else if (std.mem.eql(u8, action, "--help") or std.mem.eql(u8, action, "-h")) {
        try stdout.print("Kalamine, a keyboard layout maker\n\n", .{});
        try stdout.flush();
        try usage(stdout);
    } else {
        try stderr.print("Unknown command '{s}'\n", .{action}); // TODO: print help
        try stderr.flush();
        return error.UnknownCommand;
    }
}

fn usage(writer: *Writer) !void {
    try writer.print(
        \\Usage:
        \\  kalamine build <file> [--out=(all)] [--angle-mod] [--qwerty-shortcuts] [-h | --help]
        \\  kalamine new <output_file> [--geometry=(ISO|ANSI|ERGO)] [--altgr] [--1dk] [-h | --help]
        \\  kalamine watch <file> [--angle-mod] [-h | --help]
        \\  kalamine -h | --help
        \\  kalamine --version
        \\
        \\Options:
        \\  --out=(all)                 Keyboard drivers to generate, default all.
        \\  --angle-mod                 Apply angle-mod, which is a [ZXCVB] permutation with the LSGT key (a.k.a. ISO key).
        \\  --qwerty-shortcuts          Keep shortcuts at their Qwerty location.
        \\  --geometry=(ISO|ANSI|ERGO)  Specify keyboard geometry, default ISO.
        \\  --altgr                     Set an AltGr layer.
        \\  --1dk                       Set a custom dead key.
        \\  -h --help                   Show this screen.
        \\  --version                   Show version.
        \\
    , .{});
    try writer.flush();
}

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
