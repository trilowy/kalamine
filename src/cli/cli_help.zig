const std = @import("std");

pub const Options = enum {
    global,
    build,
    new,
    watch,
};

pub fn printTo(writer: *std.Io.Writer, options: Options) !void {
    switch (options) {
        .global => {
            try writer.writeAll(
                \\Kalamine, a keyboard layout maker
                \\
                \\Usage: kalamine [command] [options]
                \\
                \\Commands:
                \\  build <file> [options]  Convert TOML/YAML descriptions into OS-specific keyboard drivers.
                \\  new <file> [options]    Create a new TOML layout description.
                \\  watch <file> [options]  Watch a layout description file and display it in a web browser.
                \\
                \\Options:
                \\  -h --help               Show this screen.
                \\  --version               Show version.
                \\
            );
        },
        .build => {
            try writer.writeAll(
                \\Convert TOML/YAML descriptions into OS-specific keyboard drivers.
                \\
                \\Usage: kalamine build <file> [options]
                \\
                \\Options:
                \\  --out=(all|ahk|klc|keylayout|xkb_keymap|xkb_symbols|json|svg)
                \\                      Keyboard drivers to generate, default all.
                \\  --angle-mod         Apply angle-mod, which is a [ZXCVB] permutation with the
                \\                      LSGT key (a.k.a. ISO key).
                \\  --qwerty-shortcuts  Keep shortcuts at their QWERTY location.
                \\  -h --help           Show this screen.
                \\
            );
        },
        .new => {
            try writer.writeAll(
                \\Create a new TOML layout description.
                \\
                \\Usage: kalamine new <output_file> [options]
                \\
                \\Options:
                \\  --geometry=(ISO|ANSI|ERGO|ABNT|JIS|ALT)
                \\             Specify keyboard geometry, default ISO.
                \\  --altgr    Set an AltGr layer.
                \\  --1dk      Set a custom dead key.
                \\  -h --help  Show this screen.
                \\
            );
        },
        .watch => {
            try writer.writeAll(
                \\Watch a layout description file and display it in a web browser.
                \\
                \\Usage: kalamine watch <file> [options]
                \\
                \\Options:
                \\  --angle-mod  Apply angle-mod, which is a [ZXCVB] permutation with the LSGT key
                \\               (a.k.a. ISO key).
                \\  -h --help    Show this screen.
                \\
            );
        },
    }
    try writer.flush();
}
