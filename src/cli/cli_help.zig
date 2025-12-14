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
            try writer.print(
                \\Kalamine, a keyboard layout maker
                \\
                \\Usage:
                \\  kalamine build <file> [--out=(all)] [--angle-mod] [--qwerty-shortcuts] [-h | --help]
                \\  kalamine new <output_file> [--geometry=(ISO|ANSI|ERGO)] [--altgr] [--1dk] [-h | --help]
                \\  kalamine watch <file> [--angle-mod] [-h | --help]
                \\  kalamine -h | --help
                \\  kalamine --version
                \\
                \\Options:
                \\  --out=(all|keylayout|klc|xkb_keymap|xkb_symbols|svg)
                \\                              Keyboard drivers to generate, default all.
                \\  --angle-mod                 Apply angle-mod, which is a [ZXCVB] permutation with the LSGT key (a.k.a. ISO key).
                \\  --qwerty-shortcuts          Keep shortcuts at their Qwerty location.
                \\  --geometry=(ISO|ANSI|ERGO)  Specify keyboard geometry, default ISO.
                \\  --altgr                     Set an AltGr layer.
                \\  --1dk                       Set a custom dead key.
                \\  -h --help                   Show this screen.
                \\  --version                   Show version.
                \\
            , .{});
        },
        .build => {
            try writer.print(
                \\Convert TOML/YAML descriptions into OS-specific keyboard drivers.
                \\
                \\Usage:
                \\  kalamine build <file> [--out=(all)] [--angle-mod] [--qwerty-shortcuts] [-h | --help]
                \\
                \\Options:
                \\  --out=(all|keylayout|klc|xkb_keymap|xkb_symbols|svg)
                \\                      Keyboard drivers to generate, default all.
                \\  --angle-mod         Apply angle-mod, which is a [ZXCVB] permutation with the LSGT key (a.k.a. ISO key).
                \\  --qwerty-shortcuts  Keep shortcuts at their Qwerty location.
                \\  -h --help           Show this screen.
                \\
            , .{});
        },
        .new => {
            try writer.print(
                \\Create a new TOML layout description.
                \\
                \\Usage:
                \\  kalamine new <output_file> [--geometry=(ISO|ANSI|ERGO)] [--altgr] [--1dk] [-h | --help]
                \\
                \\Options:
                \\  --geometry=(ISO|ANSI|ERGO)  Specify keyboard geometry, default ISO.
                \\  --altgr                     Set an AltGr layer.
                \\  --1dk                       Set a custom dead key.
                \\  -h --help                   Show this screen.
                \\
            , .{});
        },
        .watch => {
            try writer.print(
                \\Watch a layout description file and display it in a web browser.
                \\
                \\Usage:
                \\  kalamine watch <file> [--angle-mod] [-h | --help]
                \\
                \\Options:
                \\  --angle-mod  Apply angle-mod, which is a [ZXCVB] permutation with the LSGT key (a.k.a. ISO key).
                \\  -h --help    Show this screen.
                \\
            , .{});
        },
    }
    try writer.flush();
}
