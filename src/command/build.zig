const std = @import("std");
const ParseOptions = @import("../error_handling.zig").ParseOptions;

pub const Options = struct {
    file: []const u8,
    out: Out,
    angle_mod: bool,
    qwerty_shortcuts: bool,
};

pub const Out = enum {
    all,
    keylayout,
    klc,
    xkb_keymap,
    xkb_symbols,
    svg,
};

pub fn run(options: Options, parse_options: ParseOptions) !void {
    // TODO: to implement

    _ = options;
    _ = parse_options;

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
