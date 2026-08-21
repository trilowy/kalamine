const std = @import("std");
const ParseOptions = @import("../error_handling.zig").ParseOptions;

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
    keylayout,
    klc,
    xkb_keymap,
    xkb_symbols,
    svg,
};

/// Convert TOML/YAML descriptions into OS-specific keyboard drivers
pub fn run(options: Options, parse_options: ParseOptions) !void {
    // TODO: to implement kalamine/cli.py:110
    _ = options;
    _ = parse_options;
}
