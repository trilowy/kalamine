const std = @import("std");
const ParseOptions = @import("../error_handling.zig").ParseOptions;
const toml_parser = @import("../parser/toml.zig");

pub const Options = struct {
    /// Layout file to read
    file: []const u8,
    /// Keyboard drivers to generate
    out: Out,
    /// Apply angle-mod, which is a [ZXCVB] permutation with the LSGT key (a.k.a. ISO key)
    angle_mod: bool,
    /// Keep shortcuts at their QWERTY location
    qwerty_shortcuts: bool,
};

pub const Out = enum {
    all,
    ahk,
    klc,
    keylayout,
    xkb_keymap,
    xkb_symbols,
    json,
    svg,
};

/// Convert TOML/YAML descriptions into OS-specific keyboard drivers
pub fn run(
    allocator: std.mem.Allocator,
    io: std.Io,
    options: Options,
    parse_options: ParseOptions,
) !void {
    var file = if (std.fs.path.isAbsolute(options.file))
        try std.Io.Dir.openFileAbsolute(io, options.file, .{ .mode = .read_only })
    else
        try std.Io.Dir.cwd().openFile(io, options.file, .{ .mode = .read_only });
    defer file.close(io);

    var buffer: [4 * 1024]u8 = undefined;
    var file_reader = file.reader(io, &buffer);
    const reader = &file_reader.interface;

    var keyboard_layout = try toml_parser.parseKeyboardLayoutFromToml(allocator, reader, parse_options);
    defer keyboard_layout.deinit();

    switch (options.out) {
        .all => {
            try std.Io.Dir.cwd().createDirPath(io, "dist");
            // TODO: to implement kalamine/cli.py:117/44
        },
        .ahk => {
            // TODO:
        },
        .klc => {
            // TODO:
        },
        .keylayout => {
            // TODO:
        },
        .xkb_keymap => {
            // TODO:
        },
        .xkb_symbols => {
            // TODO:
        },
        .json => {
            // TODO:
        },
        .svg => {
            // TODO:
        },
    }
}
