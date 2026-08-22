const std = @import("std");
const ParseOptions = @import("../error_handling.zig").ParseOptions;
const toml_parser = @import("../parser/toml.zig");
const ahk_v1 = @import("../generator/ahk_v1.zig");
const KeyboardLayout = @import("../layout.zig").KeyboardLayout;

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

    const file_name_without_extension = std.fs.path.stem(options.file);

    switch (options.out) {
        .all => {
            try std.Io.Dir.cwd().createDirPath(io, "dist");
            const dist_dir = try std.Io.Dir.cwd().openDir(io, "dist", .{});
            defer dist_dir.close(io);

            try ahkV1(allocator, io, dist_dir, file_name_without_extension, &keyboard_layout);
            // TODO: to implement kalamine/cli.py:117/47
        },
        .ahk => {
            // TODO:
        },
        .klc => {
            // TODO:
            // const utf16 = try std.unicode.utf8ToUtf16LeAlloc(allocator, utf8);
            // defer allocator.free(utf16);
            // try writer.writeAll(std.mem.sliceAsBytes(utf16));
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

const bom = [_]u8{ 0xEF, 0xBB, 0xBF };

fn ahkV1(
    allocator: std.mem.Allocator,
    io: std.Io,
    dir: std.Io.Dir,
    file_name_without_extension: []const u8,
    keyboard_layout: *const KeyboardLayout,
) !void {
    const file_name = try std.fmt.allocPrint(allocator, "{s}.ahk", .{file_name_without_extension});
    defer allocator.free(file_name);

    const file = try dir.createFile(io, file_name, .{});
    defer file.close(io);

    var buffer: [4 * 1024]u8 = undefined;
    var file_writer = file.writer(io, &buffer);
    const writer = &file_writer.interface;

    try writer.writeAll(&bom); // AHK scripts require a BOM

    try ahk_v1.writeLayout(writer, keyboard_layout);

    try writer.flush();
}
