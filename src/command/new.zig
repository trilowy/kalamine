const std = @import("std");

pub const Options = struct {
    output_file: []const u8,
    geometry: Geometry,
    altgr: bool,
    odk: bool,
};

pub const Geometry = enum {
    iso,
    ansi,
    ergo,
    abnt,
    jis,
    alt,
};

/// Create a new TOML layout description
pub fn run(options: Options) !void {
    // TODO: replace stdout by a file
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    try writeTomlHeader(stdout, options.geometry);
    // TODO: kalamine/help.py:145
    try stdout.flush();

    // TODO: Provide geometry choices
    // TODO: Create a new TOML layout description.
    // @click.argument("output_file", nargs=1, type=click.Path(exists=False, path_type=Path))
    // @click.option("--geometry", default="ISO", help="Specify keyboard geometry.")
    // @click.option("--altgr/--no-altgr", default=False, help="Set an AltGr layer.")
    // @click.option("--1dk/--no-1dk", "odk", default=False, help="Set a custom dead key.")
}

fn writeTomlHeader(writer: *std.Io.Writer, geometry: Geometry) !void {
    try writer.writeAll(
        \\# kalamine keyboard layout descriptor
        \\name        = "Qwerty-custom"  # full layout name, displayed in the keyboard settings
        \\name8       = "custom"         # short Windows filename: no spaces, no special chars
        \\locale      = "us"             # locale/language id
        \\variant     = "custom"         # layout variant id
        \\author      = "nobody"         # author name
        \\description = "Custom QWERTY layout"
        \\url         = "https://github.com/OneDeadKey/kalamine"
        \\version     = "0.0.1"
        \\geometry    = "
    );
    try writeGeometry(writer, geometry);
    try writer.writeAll("\"\n");
}

fn writeGeometry(writer: *std.Io.Writer, geometry: Geometry) !void {
    switch (geometry) {
        .iso => try writer.writeAll("ISO"),
        .ansi => try writer.writeAll("ANSI"),
        .ergo => try writer.writeAll("ERGO"),
        .abnt => try writer.writeAll("ABNT"),
        .jis => try writer.writeAll("JIS"),
        .alt => try writer.writeAll("ALT"),
    }
}
