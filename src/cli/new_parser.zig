const CliError = @import("error.zig").CliError;
const Options = @import("../command/new.zig").Options;

pub fn parse(_: []const []const u8) CliError!Options {
    // TODO: parse args
    return Options{
        .output_file = "TODO",
        .geometry = .iso,
        .altgr = false,
        .odk = false,
    };
}
