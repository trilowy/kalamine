const build = @import("build.zig");
const new = @import("new.zig");
const watch = @import("watch.zig");
const help = @import("../cli/cli_help.zig");

pub const Command = union(enum) {
    build: build.Options,
    new: new.Options,
    watch: watch.Options,
    version,
    help: help.Options,
};
