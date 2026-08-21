const std = @import("std");
const layout = @import("../layout.zig");
const Geometry = layout.Geometry;
const KeyboardLayout = layout.KeyboardLayout;
const toml_generator = @import("../generator/toml.zig");
const toml_parser = @import("../parser/toml.zig");
const ParseOptions = @import("../error_handling.zig").ParseOptions;

pub const Options = struct {
    /// File to create/overwrite
    output_file: []const u8,
    /// Specify keyboard geometry
    geometry: Geometry,
    /// Set an AltGr layer
    altgr: bool,
    /// Set a custom dead key
    odk: bool,
};

/// Create a new TOML layout description
pub fn run(
    allocator: std.mem.Allocator,
    io: std.Io,
    options: Options,
    parse_options: ParseOptions,
) !void {
    var file = if (std.fs.path.isAbsolute(options.output_file))
        try std.Io.Dir.createFileAbsolute(io, options.output_file, .{})
    else
        try std.Io.Dir.cwd().createFile(io, options.output_file, .{});
    defer file.close(io);

    var buffer: [4 * 1024]u8 = undefined;
    var file_writer = file.writer(io, &buffer);
    const writer = &file_writer.interface;

    try writeDummyToml(allocator, writer, &options, parse_options);

    try writer.flush();
}

fn writeDummyToml(
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    options: *const Options,
    parse_options: ParseOptions,
) !void {
    // Make a dummy keyboard layout to get full Qwerty example parsed
    var keyboard_layout = try dummyLayout(allocator, options, parse_options);
    defer keyboard_layout.deinit();

    try writer.writeAll(dummy_metadata);
    try writer.print(dummy_geometry, .{@tagName(options.geometry)});
    keyboard_layout.geometry = options.geometry;

    // Write an ASCII art description of a default layout
    if (options.odk) {
        const base = try toml_generator.getBase(allocator, &keyboard_layout);
        defer allocator.free(base);

        try writer.print(dummy_layer, .{ "base", base });

        if (options.altgr) {
            const altgr = try toml_generator.getAltgr(allocator, &keyboard_layout);
            defer allocator.free(altgr);

            try writer.print(dummy_layer, .{ "altgr", altgr });
        }

        try writer.writeAll(dummy_spacebar_odk);
    } else if (options.altgr) {
        const full = try toml_generator.getFull(allocator, &keyboard_layout);
        defer allocator.free(full);

        try writer.print(dummy_layer, .{ "full", full });
    } else {
        const base = try toml_generator.getBase(allocator, &keyboard_layout);
        defer allocator.free(base);

        try writer.print(dummy_layer, .{ "base", base });
    }

    try writer.writeAll(dummy_help);
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

// TODO: see if user_guide.yaml and dead_keys.yml will be used again
// kalamine/help.py:149/47
const dummy_help =
    \\
    \\
    \\# --------------------------------------------------------------------------------
    \\# Layers
    \\# --------------------------------------------------------------------------------
    \\#
    \\# ### base
    \\#
    \\# The `base` layer contains the base and shifted keys:
    \\#
    \\#                    +-----+
    \\#     shift -------> | ?   |
    \\#     base --------> | /   |
    \\#                    +-----+
    \\#
    \\# When the base and shift keys correspond to the same character, you may only
    \\# specify the uppercase char:
    \\#
    \\#                    +-----+
    \\#     shift -------> | A   |
    \\#     (base = a) --> |     |
    \\#                    +-----+
    \\#
    \\#
    \\# ### altgr
    \\#
    \\# The `altgr` layer contains the altgr and shift+altgr symbols:
    \\#
    \\#                    +-----+
    \\#                    |     | <----- (altgr+shift+key is undefined)
    \\#                    |   { | <----- altgr+key = {
    \\#                    +-----+
    \\#
    \\#
    \\# ### full
    \\#
    \\# The `full` view lets you specify the `base` and `altgr` levels together:
    \\#
    \\#                    +-----+
    \\#     shift -------> | A   | <----- (altgr+shift+key is undefined)
    \\#     (base = a) --> |   { | <----- altgr+key = {
    \\#                    +-----+
    \\
    \\
    \\# --------------------------------------------------------------------------------
    \\# Dead Keys
    \\# --------------------------------------------------------------------------------
    \\#
    \\# ### Usage
    \\#
    \\# Dead keys are preceded by a `*` sign. They can be used in the `base` layer:
    \\#
    \\#                    +-----+
    \\#     shift -------> |*"   |  = dead diaeresis
    \\#     base --------> |*´   |  = dead acute accent
    \\#                    +-----+
    \\#
    \\# … as well as in the `altgr` layer:
    \\#
    \\#                    +-----+
    \\#                    |  *" | <----- altgr+shift+key = dead diaeresis
    \\#                    |  *´ | <----- altgr+key       = dead acute accent
    \\#                    +-----+
    \\#
    \\# … and combined in the `full` layer:
    \\#
    \\#                     +-----+
    \\#   shift+key = A --> | A*" | <----- altgr+shift+key = dead diaeresis
    \\#         key = a --> | a*´ | <----- altgr+key       = dead acute accent
    \\#                     +-----+
    \\#
    \\#
    \\# ### Standard Dead Keys
    \\#
    \\# The following dead keys are supported, and their behavior cannot be customized:
    \\#
    \\#     id  XKB name          base -> accented chars
    \\#     ----------------------------------------------------------------------------
    \\#     *`  grave             AaEeIiNnOoUuWwYyЕеИи
    \\#                        -> ÀàÈèÌìǸǹÒòÙùẀẁỲỳЀѐЍѝ
    \\#     *‟  doublegrave       AaEeIiOoRrUuѴѴ
    \\#                        -> ȀȁȄȅȈȉȌȍȐȑȔȕѶѷ
    \\#     *´  acute             AaCcEeGgIiKkLlMmNnOoPpRrSsUuWwYyZzΑαΕεΗηΙιΟοΥυΩωГгКк
    \\#                        -> ÁáĆćÉéǴǵÍíḰḱĹĺḾḿŃńÓóṔṕŔŕŚśÚúẂẃÝýŹźΆάΈέΉήΊίΌόΎύΏώЃѓЌќ
    \\#     *”  doubleacute       OoUuУу
    \\#                        -> ŐőŰűӲӳ
    \\#     *^  circumflex        AaCcEeGgHhIiJjOoSsUuWwYyZz0123456789()+-=
    \\#                        -> ÂâĈĉÊêĜĝĤĥÎîĴĵÔôŜŝÛûŴŵŶŷẐẑ⁰¹²³⁴⁵⁶⁷⁸⁹⁽⁾⁺⁻⁼
    \\#     *ˇ  caron             AaCcDdEeGgHhIiKkLlNnOoRrSsTtUuZzƷʒ0123456789()+-=
    \\#                        -> ǍǎČčĎďĚěǦǧȞȟǏǐǨǩĽľŇňǑǒŘřŠšŤťǓǔŽžǮǯ₀₁₂₃₄₅₆₇₈₉₍₎₊₋₌
    \\#     *˘  breve             AaEeGgIiOoUuΑαΙιΥυАаЕеЖжИиУу
    \\#                        -> ĂăĔĕĞğĬĭŎŏŬŭᾸᾰῘῐῨῠӐӑӖӗӁӂЙйЎў
    \\#     *⁻  invertedbreve     AaEeIiOoUuRr
    \\#                        -> ȂȃȆȇȊȋȎȏȖȗȒȓ
    \\#     *~  tilde             AaEeIiNnOoUuVvYy<>=
    \\#                        -> ÃãẼẽĨĩÑñÕõŨũṼṽỸỹ≲≳≃
    \\#     *¯  macron            AaÆæEeGgIiOoUuYy
    \\#                        -> ĀāǢǣĒēḠḡĪīŌōŪūȲȳ
    \\#     *¨  diaeresis         AaEeHhIiOotUuWwXxYyΙιΥυАаЕеӘәЖжЗзИиІіОоӨөУуЧчЫыЭэ
    \\#                        -> ÄäËëḦḧÏïÖöẗÜüẄẅẌẍŸÿΪϊΫϋӒӓЁёӚӛӜӝӞӟӤӥЇїӦӧӪӫӰӱӴӵӸӹӬӭ
    \\#     *˚  abovering         AaUuwy
    \\#                        -> ÅåŮůẘẙ
    \\#     *¸  cedilla           CcDdEeGgHhKkLlNnRrSsTt
    \\#                        -> ÇçḐḑȨȩĢģḨḩĶķĻļŅņŖŗŞşŢţ
    \\#     *,  belowcomma        SsTt
    \\#                        -> ȘșȚț
    \\#     *˛  ogonek            AaEeIiOoUu
    \\#                        -> ĄąĘęĮįǪǫŲų
    \\#     */  stroke            AaBbCcDdEeGgHhIiJjLlOoPpRrTtUuYyZz<≤≥>=
    \\#                        -> ȺⱥɃƀȻȼĐđɆɇǤǥĦħƗɨɈɉŁłØøⱣᵽɌɍŦŧɄʉɎɏƵƶ≮≰≱≯≠
    \\#     *˙  abovedot          AaBbCcDdEeFfGgHhIijLlMmNnOoPpRrSsTtWwXxYyZz
    \\#                        -> ȦȧḂḃĊċḊḋĖėḞḟĠġḢḣİıȷĿŀṀṁṄṅȮȯṖṗṘṙṠṡṪṫẆẇẊẋẎẏŻż
    \\#     *.  belowdot          AaBbDdEeHhIiKkLlMmNnOoRrSsTtUuVvWwYyZz
    \\#                        -> ẠạḄḅḌḍẸẹḤḥỊịḲḳḶḷṂṃṆṇỌọṚṛṢṣṬṭỤụṾṿẈẉỴỵẒẓ
    \\#     *µ  greek             AaBbDdEeFfGgHhIiJjKkLlMmNnOoPpQqRrSsTtUuWwXxYyZz
    \\#                        -> ΑαΒβΔδΕεΦφΓγΗηΙιΘθΚκΛλΜμΝνΟοΠπΧχΡρΣσΤτΥυΩωΞξΨψΖζ
    \\#     *¤  currency          AaBbÇCçcDdEeFfGgHhIiKkLlMmNnOoPpRrSsTtþÞUuWwYy
    \\#                        -> ₳؋₱฿₵₡₵¢₯₫₠€₣ƒ₲₲₴₴៛﷼₭₭₤£ℳ₥₦₦૱௹₧₰₨₢$₪₮৳৲৲圓元₩₩円¥
    \\#
    \\# ### Custom Dead Key
    \\#
    \\# There is one dead key (1dk), noted `**`, that can be customized by specifying
    \\# how it modifies each character in the `base` layer:
    \\#
    \\#                    +-----+
    \\#     shift -------> | ? ¿ | <----- 1dk, shift+key
    \\#     base --------> | / ÷ | <----- 1dk, key
    \\#                    +-----+
    \\#
    \\# When the base and shift keys correspond to the same accented character, you may
    \\# only specify the lowercase accented char in the `base` layer:
    \\#
    \\#                    +-----+
    \\#     shift -------> | A   | <----- (1dk, shift+key = À)
    \\#     (base = a) --> |   à | <----- 1dk, key = à
    \\#                    +-----+
    \\#
    \\# You may also chain dead keys by specifying a dead key in the `1dk` layer:
    \\#
    \\#                    +-----+
    \\#     shift -------> | G   |
    \\#     (base = g) --> |  *µ | <----- 1dk, key = dead Greek
    \\#                    +-----+
    \\#
    \\# **Warning:** chained dead keys are not supported by MSKLC, and KbdEdit will be
    \\# required to build a Windows driver for such a keyboard layout.
    \\
    \\
    \\# --------------------------------------------------------------------------------
    \\# Space Bar
    \\# --------------------------------------------------------------------------------
    \\#
    \\# Kalamine descriptor files have an optional section to define specific behaviors
    \\# of the space bar in non-base layers:
    \\#
    \\#     [spacebar]
    \\#     shift       = "\u202f"  # NARROW NO-BREAK SPACE
    \\#     altgr       = "\u0020"  # SPACE
    \\#     altgr_shift = "\u00a0"  # NO-BREAK SPACE
    \\#     1dk         = "\u2019"  # RIGHT SINGLE QUOTATION MARK
    \\#     1dk_shift   = "\u2019"  # RIGHT SINGLE QUOTATION MARK
    \\#
    \\# Kalamine doesn’t support non-space chars on the `base` layer for the space bar.
    \\# Space characters outside of the space bar are not supported either.
    \\
;
