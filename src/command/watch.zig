const ParseOptions = @import("../error_handling.zig").ParseOptions;

pub const Options = struct {
    /// Layout file to watch
    file: []const u8,
    /// Apply angle-mod, which is a [ZXCVB] permutation with the LSGT key (a.k.a. ISO key)
    angle_mod: bool,
};

/// Watch a layout description file and display it in a web browser
pub fn run(options: Options, parse_options: ParseOptions) !void {
    _ = options;
    _ = parse_options;
}
