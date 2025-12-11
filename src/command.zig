const std = @import("std");
const app = @import("build.zig.zon");
const Writer = std.Io.Writer;

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
