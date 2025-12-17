const std = @import("std");
const toml = @import("toml");
const layout = @import("../layout/layout.zig");
const Geometry = layout.Geometry;
const KeyboardLayout = layout.KeyboardLayout;

pub const Options = struct {
    output_file: []const u8,
    geometry: Geometry,
    altgr: bool,
    odk: bool,
};

/// Create a new TOML layout description
pub fn run(options: Options) !void {
    // TODO: replace stdout by a file
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    try writeTomlHeader(stdout, options.geometry);
    try writeLayout(stdout, options);
    // TODO: kalamine/help.py:145
    try stdout.flush();

    // TODO: test of toml lib
    const file_content =
        \\# kalamine keyboard layout descriptor
        \\name        = "Qwerty-custom"  # full layout name, displayed in the keyboard settings
        \\name8       = "custom"         # short Windows filename: no spaces, no special chars
        \\locale      = "us"             # locale/language id
        \\variant     = "custom"         # layout variant id
        \\author      = "nobody"         # author name
        \\description = "Custom QWERTY layout"
        \\url         = "https://github.com/OneDeadKey/kalamine"
        \\version     = "0.0.1"
        \\geometry    = "ANSI"
        \\
    ;

    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    const allocator = debug_allocator.allocator();
    defer _ = debug_allocator.deinit();

    var parser = toml.Parser(KeyboardLayout).init(allocator);
    defer parser.deinit();

    var result = try parser.parseString(file_content);
    defer result.deinit();

    const config = result.value;
    std.debug.print("name: {s}\nname8: {s}\ngeometry: {any}\n", .{ config.name.?, config.name8, config.geometry });
    // TODO: end of test

    std.debug.print("{any}\n", .{options.geometry.getKeys()});
}

fn writeTomlHeader(writer: *std.Io.Writer, geometry: Geometry) !void {
    try writer.print(
        \\# kalamine keyboard layout descriptor
        \\name        = "Qwerty-custom"  # full layout name, displayed in the keyboard settings
        \\name8       = "custom"         # short Windows filename: no spaces, no special chars
        \\locale      = "us"             # locale/language id
        \\variant     = "custom"         # layout variant id
        \\author      = "nobody"         # author name
        \\description = "Custom QWERTY layout"
        \\url         = "https://github.com/OneDeadKey/kalamine"
        \\version     = "0.0.1"
        \\geometry    = "{s}"
        \\
    , .{@tagName(geometry)});
}

/// Write an ASCII art description of a default layout
fn writeLayout(writer: *std.Io.Writer, options: Options) !void {
    // TODO:
    try writer.writeAll(alpha_layout);
    _ = options;

    // TODO: kalamine/help.py:76
    // TODO: kalamine/help.py:92
    // TODO: kalamine/layout.py:142

    // TODO: kalamine/help.py:108
}

const alpha_layout =
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
    \\
;

const odk_layout =
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
    \\
;

const altgr_layout =
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
    \\┃ Ctrl  ┃ super ┃ Alt   ┃ ␣                              ┃ AltGr ┃ super ┃ menu  ┃ Ctrl  ┃
    \\┗━━━━━━━┻━━━━━━━┻━━━━━━━┹────────────────────────────────┺━━━━━━━┻━━━━━━━┻━━━━━━━┻━━━━━━━┛
    \\
;
