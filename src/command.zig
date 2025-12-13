const std = @import("std");
const app = @import("build.zig.zon");
const Writer = std.Io.Writer;

const Command = union(enum) {
    build: BuildCommand,
    new: NewCommand,
    watch: WatchCommand,
    version,
    help: HelpCommand,
};

const BuildCommand = struct {
    file: []const u8,
    out: enum { all }, // TODO: add other out options + help
    angle_mod: bool,
    qwerty_shortcuts: bool,
};

const NewCommand = struct {
    output_file: []const u8,
    geometry: enum { iso, ansi, ergo },
    altgr: bool,
    odk: bool,
};

const WatchCommand = struct {
    file: []const u8,
    angle_mod: bool,
};

const HelpCommand = enum {
    global,
    build,
    new,
    watch,

    // Keep this function next to command parsing to keep it up to date
    pub fn print(self: HelpCommand, writer: *Writer) !void {
        switch (self) {
            .global => {
                try writer.print(
                    \\Kalamine, a keyboard layout maker
                    \\
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
            },
            .build => {
                try writer.print(
                    \\Convert TOML/YAML descriptions into OS-specific keyboard drivers.
                    \\
                    \\Usage:
                    \\  kalamine build <file> [--out=(all)] [--angle-mod] [--qwerty-shortcuts] [-h | --help]
                    \\
                    \\Options:
                    \\  --out=(all)         Keyboard drivers to generate, default all.
                    \\  --angle-mod         Apply angle-mod, which is a [ZXCVB] permutation with the LSGT key (a.k.a. ISO key).
                    \\  --qwerty-shortcuts  Keep shortcuts at their Qwerty location.
                    \\  -h --help           Show this screen.
                    \\
                , .{});
            },
            .new => {
                try writer.print(
                    \\Create a new TOML layout description.
                    \\
                    \\Usage:
                    \\  kalamine new <output_file> [--geometry=(ISO|ANSI|ERGO)] [--altgr] [--1dk] [-h | --help]
                    \\
                    \\Options:
                    \\  --geometry=(ISO|ANSI|ERGO)  Specify keyboard geometry, default ISO.
                    \\  --altgr                     Set an AltGr layer.
                    \\  --1dk                       Set a custom dead key.
                    \\  -h --help                   Show this screen.
                    \\
                , .{});
            },
            .watch => {
                try writer.print(
                    \\Watch a layout description file and display it in a web browser.
                    \\
                    \\Usage:
                    \\  kalamine watch <file> [--angle-mod] [-h | --help]
                    \\
                    \\Options:
                    \\  --angle-mod  Apply angle-mod, which is a [ZXCVB] permutation with the LSGT key (a.k.a. ISO key).
                    \\  -h --help    Show this screen.
                    \\
                , .{});
            },
        }
        try writer.flush();
    }
};

pub fn parse(args: []const []const u8) !Command {
    // Must at least have one arg for the command
    const action = if (args.len > 1) args[1] else {
        return error.MissingArg;
    };

    if (std.mem.eql(u8, action, "build")) {
        // TODO: parse args
        return Command{
            .build = BuildCommand{
                .file = "TODO",
                .out = .all,
                .angle_mod = false,
                .qwerty_shortcuts = false,
            },
        };
    } else if (std.mem.eql(u8, action, "new")) {
        // TODO: parse args
        return Command{
            .new = NewCommand{
                .output_file = "TODO",
                .geometry = .iso,
                .altgr = false,
                .odk = false,
            },
        };
    } else if (std.mem.eql(u8, action, "watch")) {
        // TODO: parse args
        return Command{
            .watch = WatchCommand{
                .file = "TODO",
                .angle_mod = false,
            },
        };
    } else if (std.mem.eql(u8, action, "--version")) {
        return .version;
    } else if (std.mem.eql(u8, action, "--help") or std.mem.eql(u8, action, "-h")) {
        // TODO: parse args
        return .{ .help = .global };
    } else {
        return error.UnknownCommand;
    }
}

pub fn build() !void {
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
}

pub fn new() !void {
    // TODO: Provide geometry choices
    // TODO: Create a new TOML layout description.
    // @click.argument("output_file", nargs=1, type=click.Path(exists=False, path_type=Path))
    // @click.option("--geometry", default="ISO", help="Specify keyboard geometry.")
    // @click.option("--altgr/--no-altgr", default=False, help="Set an AltGr layer.")
    // @click.option("--1dk/--no-1dk", "odk", default=False, help="Set a custom dead key.")
}

pub fn watch() !void {
    // TODO: Watch a layout description file and display it in a web browser.
    // @click.argument("filepath", nargs=1, type=click.Path(exists=True, path_type=Path))
    // @click.option(
    //     "--angle-mod/--no-angle-mod",
    //     default=False,
    //     help="Apply Angle-Mod (which is a [ZXCVB] permutation with the LSGT key (a.k.a. ISO key))",
    // )
}

pub fn version(writer: *Writer) !void {
    try writer.print("{s}\n", .{app.version});
    try writer.flush();
}

test "parse missing arg" {
    const args = [_][:0]const u8{"kalamine"};
    const result = parse(&args);
    try std.testing.expectEqual(error.MissingArg, result);
}

test "parse build" {
    const args = [_][:0]const u8{ "kalamine", "build" };
    const result = parse(&args);
    try std.testing.expectEqual(
        Command{
            .build = BuildCommand{
                .file = "TODO",
                .out = .all,
                .angle_mod = false,
                .qwerty_shortcuts = false,
            },
        },
        result,
    );
}

test "parse new" {
    const args = [_][:0]const u8{ "kalamine", "new" };
    const result = parse(&args);
    try std.testing.expectEqual(
        Command{
            .new = NewCommand{
                .output_file = "TODO",
                .geometry = .iso,
                .altgr = false,
                .odk = false,
            },
        },
        result,
    );
}

test "parse watch" {
    const args = [_][:0]const u8{ "kalamine", "watch" };
    const result = parse(&args);
    try std.testing.expectEqual(
        Command{
            .watch = WatchCommand{
                .file = "TODO",
                .angle_mod = false,
            },
        },
        result,
    );
}

test "parse --version" {
    const args = [_][:0]const u8{ "kalamine", "--version" };
    const result = parse(&args);
    try std.testing.expectEqual(.version, result);
}

test "parse --help" {
    const args = [_][:0]const u8{ "kalamine", "--help" };
    const result = parse(&args);
    try std.testing.expectEqual(Command{ .help = .global }, result);
}

test "parse -h" {
    const args = [_][:0]const u8{ "kalamine", "-h" };
    const result = parse(&args);
    try std.testing.expectEqual(Command{ .help = .global }, result);
}

test "parse unknown" {
    const args = [_][:0]const u8{ "kalamine", "unknown" };
    const result = parse(&args);
    try std.testing.expectEqual(error.UnknownCommand, result);
}
