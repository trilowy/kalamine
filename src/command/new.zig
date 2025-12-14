pub const Options = struct {
    output_file: []const u8,
    geometry: enum { iso, ansi, ergo },
    altgr: bool,
    odk: bool,
};

pub fn run() !void {
    // TODO: Provide geometry choices
    // TODO: Create a new TOML layout description.
    // @click.argument("output_file", nargs=1, type=click.Path(exists=False, path_type=Path))
    // @click.option("--geometry", default="ISO", help="Specify keyboard geometry.")
    // @click.option("--altgr/--no-altgr", default=False, help="Set an AltGr layer.")
    // @click.option("--1dk/--no-1dk", "odk", default=False, help="Set a custom dead key.")
}
