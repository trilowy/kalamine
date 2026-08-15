const std = @import("std");
const layout = @import("../layout.zig");
const Geometry = layout.Geometry;
const KeyboardLayout = layout.KeyboardLayout;
const toml_generator = @import("../generator/toml.zig");
const toml_parser = @import("../parser/toml.zig");
const error_handling = @import("../error_handling.zig");
const Diagnostic = error_handling.Diagnostic;
const ParseOptions = error_handling.ParseOptions;

pub const Options = struct {
    output_file: []const u8,
    geometry: Geometry,
    altgr: bool,
    odk: bool,
};

/// Create a new TOML layout description
pub fn run(allocator: std.mem.Allocator, options: Options, parse_options: ParseOptions) !void {
    // TODO: at the end, check if the result is the same than the Python version
    // TODO: at the end of coding this function "new", see if there is useless imports
    // TODO: check if 2 kinds of "é" can be compared
    // const str = "He\u{301}"; // Hé
    // TODO: replace stdout by a file and put it nearer to were it is used
    // https://pedropark99.github.io/zig-book/Chapters/12-file-op.html
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    // Make a dummy keyboard layout to get full Qwerty example parsed
    var keyboard_layout = try dummyLayout(allocator, &options, parse_options);
    defer keyboard_layout.deinit();

    try stdout.writeAll(dummy_metadata);
    try stdout.print(dummy_geometry, .{@tagName(options.geometry)});
    keyboard_layout.geometry = options.geometry;

    // Write an ASCII art description of a default layout
    if (options.odk) {
        // TODO: kalamine/layout.py:404
        // TODO: kalamine/help.py:116 draw_layout
        // TODO: kalamine/help.py:145
        const base = try toml_generator.getBase(allocator, &keyboard_layout);
        defer allocator.free(base);

        try stdout.print(dummy_layer, .{ "base", base });

        if (options.altgr) {
            const altgr = try toml_generator.getAltgr(allocator, &keyboard_layout);
            defer allocator.free(altgr);

            try stdout.print(dummy_layer, .{ "altgr", altgr });
        }

        try stdout.writeAll(dummy_spacebar_odk);
    } else if (options.altgr) {
        const full = try toml_generator.getFull(allocator, &keyboard_layout);
        defer allocator.free(full);

        try stdout.print(dummy_layer, .{ "full", full });
    } else {
        const base = try toml_generator.getBase(allocator, &keyboard_layout);
        defer allocator.free(base);

        try stdout.print(dummy_layer, .{ "base", base });
    }

    // TODO: kalamine/help.py:149
    // TODO: kalamine/help.py:47 user_guide.yaml

    try stdout.flush();
}

/// Create a dummy (QWERTY) layout with the given characteristics
fn dummyLayout(
    allocator: std.mem.Allocator,
    options: *const Options,
    parse_options: ParseOptions,
) !KeyboardLayout {
    var file_content = std.ArrayList(u8).empty;
    defer file_content.deinit(allocator);

    try file_content.appendSlice(allocator, dummy_metadata);
    try file_content.print(allocator, dummy_geometry, .{@tagName(Geometry.ANSI)});

    const base = if (options.odk) dummy_odk_layout else dummy_alpha_layout;
    try file_content.print(allocator, dummy_layer, .{ "base", base });

    if (options.altgr) {
        try file_content.print(allocator, dummy_layer, .{ "altgr", dummy_altgr_layout });
    }

    // TODO: kalamine/help.py:96 web scan codes, needed for the web?

    var reader = std.Io.Reader.fixed(file_content.items);
    return toml_parser.parseKeyboardLayoutFromToml(allocator, &reader, parse_options);
}

const dummy_metadata =
    \\# kalamine keyboard layout descriptor
    \\name        = "Qwerty-custom"  # full layout name, displayed in the keyboard settings
    \\name8       = "custom"         # short Windows filename: no spaces, no special chars
    \\locale      = "en-US"          # locale/language id
    \\variant     = "custom"         # layout variant id
    \\author      = "nobody"         # author name
    \\description = "Custom QWERTY layout"
    \\url         = "https://github.com/OneDeadKey/kalamine"
    \\version     = "0.0.1"
    \\
;

const dummy_geometry =
    \\geometry    = "{s}"
    \\
;

const dummy_layer =
    \\
    \\{s} = '''
    \\{s}
    \\'''
    \\
;

const dummy_alpha_layout =
    \\┌─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┲━━━━━━━━━━┓
    \\│ ~   │ !   │ @   │ #   │ $   │ %   │ ^   │ &   │ *   │ (   │ )   │ _   │ +   ┃          ┃
    \\│ `   │ 1   │ 2   │ 3   │ 4   │ 5   │ 6   │ 7   │ 8   │ 9   │ 0   │ -   │ =   ┃ ⌫        ┃
    \\┢━━━━━┷━━┱──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┺━━┯━━━━━━━┩
    \\┃        ┃ Q   │ W   │ E   │ R   │ T   │ Y   │ U   │ I   │ O   │ P   │ {   │ }   │ |     │
    \\┃ ↹      ┃     │     │     │     │     │     │     │     │     │     │ [   │ ]   │ \     │
    \\┣━━━━━━━━┻┱────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┲━━━━┷━━━━━━━┪
    \\┃         ┃ A   │ S   │ D   │ F   │ G   │ H   │ J   │ K   │ L   │ :   │ "   ┃            ┃
    \\┃ ⇬       ┃     │     │     │     │     │     │     │     │     │ ;   │ '   ┃ ⏎          ┃
    \\┣━━━━━━━━━┻━━┱──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┲━━┻━━━━━━━━━━━━┫
    \\┃            ┃ Z   │ X   │ C   │ V   │ B   │ N   │ M   │ <   │ >   │ ?   ┃               ┃
    \\┃ ⇧          ┃     │     │     │     │     │     │     │ ,   │ .   │ /   ┃ ⇧             ┃
    \\┣━━━━━━━┳━━━━┻━━┳━━┷━━━━┱┴─────┴─────┴─────┴─────┴─────┴─┲━━━┷━━━┳━┷━━━━━╋━━━━━━━┳━━━━━━━┫
    \\┃       ┃       ┃       ┃                                ┃       ┃       ┃       ┃       ┃
    \\┃ Ctrl  ┃ super ┃ Alt   ┃ ␣                              ┃ Alt   ┃ super ┃ menu  ┃ Ctrl  ┃
    \\┗━━━━━━━┻━━━━━━━┻━━━━━━━┹────────────────────────────────┺━━━━━━━┻━━━━━━━┻━━━━━━━┻━━━━━━━┛
;

const dummy_odk_layout =
    \\┌─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┲━━━━━━━━━━┓
    \\│ ~   │ !   │ @   │ #   │ $   │ %   │ ^   │ &   │ *   │ (   │ )   │ _   │ +   ┃          ┃
    \\│ `   │ 1   │ 2 « │ 3 » │ 4   │ 5 € │ 6   │ 7   │ 8   │ 9   │ 0   │ -   │ =   ┃ ⌫        ┃
    \\┢━━━━━┷━━┱──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┺━━┯━━━━━━━┩
    \\┃        ┃ Q   │ W   │ E   │ R   │ T   │ Y   │ U   │ I   │ O   │ P   │ {   │ }   │ |     │
    \\┃ ↹      ┃     │     │   é │     │     │   ý │   ú │   í │   ó │     │ [   │ ]   │ \     │
    \\┣━━━━━━━━┻┱────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┲━━━━┷━━━━━━━┪
    \\┃         ┃ A   │ S   │ D   │ F   │ G   │ H   │ J   │ K   │ L   │ :   │*¨   ┃            ┃
    \\┃ ⇬       ┃   á │     │     │     │     │     │     │     │     │ ;   │** ' ┃ ⏎          ┃
    \\┣━━━━━━━━━┻━━┱──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┲━━┻━━━━━━━━━━━━┫
    \\┃            ┃ Z   │ X   │ C   │ V   │ B   │ N   │ M   │ < • │ >   │ ?   ┃               ┃
    \\┃ ⇧          ┃     │     │   ç │     │     │     │   µ │ , · │ . … │ /   ┃ ⇧             ┃
    \\┣━━━━━━━┳━━━━┻━━┳━━┷━━━━┱┴─────┴─────┴─────┴─────┴─────┴─┲━━━┷━━━┳━┷━━━━━╋━━━━━━━┳━━━━━━━┫
    \\┃       ┃       ┃       ┃                                ┃       ┃       ┃       ┃       ┃
    \\┃ Ctrl  ┃ super ┃ Alt   ┃ ␣                              ┃ Alt   ┃ super ┃ menu  ┃ Ctrl  ┃
    \\┗━━━━━━━┻━━━━━━━┻━━━━━━━┹────────────────────────────────┺━━━━━━━┻━━━━━━━┻━━━━━━━┻━━━━━━━┛
;

const dummy_altgr_layout =
    \\┌─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┲━━━━━━━━━━┓
    \\│  *~ │     │     │     │     │     │     │     │     │     │     │     │     ┃          ┃
    \\│  *` │     │     │     │     │     │  *^ │     │     │     │     │     │     ┃ ⌫        ┃
    \\┢━━━━━┷━━┱──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┺━━┯━━━━━━━┩
    \\┃        ┃     │     │     │     │     │     │     │     │     │     │     │     │       │
    \\┃ ↹      ┃   @ │   < │   > │   $ │   % │   ^ │   & │   * │   ' │   ` │     │     │       │
    \\┣━━━━━━━━┻┱────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┲━━━━┷━━━━━━━┪
    \\┃         ┃     │     │     │     │     │     │     │     │     │     │  *¨ ┃            ┃
    \\┃ ⇬       ┃   { │   ( │   ) │   } │   = │   \ │   + │   - │   / │   " │  *´ ┃ ⏎          ┃
    \\┣━━━━━━━━━┻━━┱──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┲━━┻━━━━━━━━━━━━┫
    \\┃            ┃     │     │     │     │     │     │     │     │     │     ┃               ┃
    \\┃ ⇧          ┃   ~ │   [ │   ] │   _ │   # │   | │   ! │   ; │   : │   ? ┃ ⇧             ┃
    \\┣━━━━━━━┳━━━━┻━━┳━━┷━━━━┱┴─────┴─────┴─────┴─────┴─────┴─┲━━━┷━━━┳━┷━━━━━╋━━━━━━━┳━━━━━━━┫
    \\┃       ┃       ┃       ┃                                ┃       ┃       ┃       ┃       ┃
    \\┃ Ctrl  ┃ super ┃ Alt   ┃ ␣                              ┃ Alt   ┃ super ┃ menu  ┃ Ctrl  ┃
    \\┗━━━━━━━┻━━━━━━━┻━━━━━━━┹────────────────────────────────┺━━━━━━━┻━━━━━━━┻━━━━━━━┻━━━━━━━┛
;

const dummy_spacebar_odk =
    \\
    \\[spacebar]
    \\1dk         = "'"  # apostrophe
    \\1dk_shift   = "'"  # apostrophe
    \\
;
