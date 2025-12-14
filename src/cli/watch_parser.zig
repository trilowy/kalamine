const CliError = @import("error.zig").CliError;
const Options = @import("../command/watch.zig").Options;

pub fn parse(_: []const []const u8) CliError!Options {
    // TODO: parse args
    return Options{
        .file = "TODO",
        .angle_mod = false,
    };
}
