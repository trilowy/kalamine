const std = @import("std");
const toml = @import("toml");
const layout_mod = @import("../layout.zig");
const KeyboardLayout = layout_mod.KeyboardLayout;
const Layer = layout_mod.Layer;
const Geometry = layout_mod.Geometry;
const KeyCode = layout_mod.KeyCode;
const error_handling = @import("../error_handling.zig");
const ParseOptions = error_handling.ParseOptions;
const Diagnostic = error_handling.Diagnostic;
const ParsingError = error_handling.ParsingError;
const LetterCasing = @import("LetterCasing");
const Graphemes = @import("Graphemes");
const Grapheme = Graphemes.Grapheme;

pub const ParsedKey = struct {
    left_up: ?[]const u8 = null,
    left_down: ?[]const u8 = null,
    right_up: ?[]const u8 = null,
    right_down: ?[]const u8 = null,
};

pub const nb_lines_per_key = 3;
pub const nb_columns_per_key = 6;

const default_spacebar_base = " ";
const default_spacebar_shift = " ";
const default_spacebar_altgr = " ";
const default_spacebar_altgr_shift = " ";
const default_spacebar_odk = "'";
const default_spacebar_odk_shift = "'";

const TomlContent = struct {
    name: ?[]const u8,
    name8: ?[]const u8,
    locale: ?[]const u8,
    variant: ?[]const u8,
    author: ?[]const u8,
    description: ?[]const u8,
    url: ?[]const u8,
    version: ?[]const u8,
    geometry: ?Geometry,
    base: ?[]const u8,
    full: ?[]const u8,
    altgr: ?[]const u8,
    spacebar: ?TomlContentSpacebar,
};

const TomlContentSpacebar = struct {
    shift: ?[]const u8,
    altgr: ?[]const u8,
    altgr_shift: ?[]const u8,
    @"1dk": ?[]const u8,
    @"1dk_shift": ?[]const u8,
};

/// Deinitialize with `deinit`
/// In case of error, deinitialize the error message if present in options
pub fn parseKeyboardLayoutFromToml(
    allocator: std.mem.Allocator,
    reader: *std.Io.Reader,
    options: ParseOptions,
) !KeyboardLayout {
    // Read all
    const toml_content: []const u8 = try reader.allocRemaining(allocator, .unlimited);
    defer allocator.free(toml_content);

    // Parse TOML
    var toml_parser = toml.Parser(TomlContent).init(allocator);
    defer toml_parser.deinit();

    var result = try toml_parser.parseString(toml_content);
    defer result.deinit();

    const parsed_toml = result.value;

    var arena_allocator = std.heap.ArenaAllocator.init(allocator);
    const arena = arena_allocator.allocator();
    errdefer arena_allocator.deinit();

    // Own the memory of each field to free the rest
    const name = if (parsed_toml.name) |name|
        try arena.dupe(u8, name)
    else {
        if (options.diagnostic) |diag| diag.arg = "name";
        return ParsingError.MissingAttribute;
    };

    const name8 = if (parsed_toml.name8) |name8|
        try arena.dupe(u8, name8)
    else
        try arena.dupe(u8, name[0..@min(name.len, 8)]);

    const locale = if (parsed_toml.locale) |locale|
        try arena.dupe(u8, locale)
    else
        null;

    const variant = if (parsed_toml.variant) |variant|
        try arena.dupe(u8, variant)
    else
        null;

    const author = if (parsed_toml.author) |author|
        try arena.dupe(u8, author)
    else
        null;

    const description = if (parsed_toml.description) |description|
        try arena.dupe(u8, description)
    else
        null;

    const url = if (parsed_toml.url) |url|
        try arena.dupe(u8, url)
    else
        null;

    const version = if (parsed_toml.version) |version|
        try arena.dupe(u8, version)
    else
        null;

    const geometry = if (parsed_toml.geometry) |geometry|
        geometry
    else {
        if (options.diagnostic) |diag| diag.arg = "geometry";
        return ParsingError.MissingAttribute;
    };

    var layers = std.AutoHashMapUnmanaged(Layer, std.AutoHashMapUnmanaged(KeyCode, []const u8)).empty;
    for (std.enums.values(Layer)) |layer| {
        try layers.put(arena, layer, std.AutoHashMapUnmanaged(KeyCode, []const u8).empty);
    }

    var keyboard_layout = KeyboardLayout{
        .arena_allocator = arena_allocator,
        .name = name,
        .name8 = name8,
        .locale = locale,
        .variant = variant,
        .author = author,
        .description = description,
        .url = url,
        .version = version,
        .geometry = geometry,
        .layers = layers,
    };

    // TODO: line of the TOML is better for the feedback in diagnostic
    if (parsed_toml.full) |full_to_parse| {
        if (options.diagnostic) |diag| diag.arg = "full";

        var keymap = try parseLayout(allocator, keyboard_layout.geometry, full_to_parse, options);
        defer keymap.deinit(allocator);

        // PERF: loop on multiple layers at the same time?
        try parseTemplate(allocator, &keyboard_layout, &keymap, Layer.base);
        try parseTemplate(allocator, &keyboard_layout, &keymap, Layer.altgr);

        keyboard_layout.has_altgr = true;

        if (options.diagnostic) |diag| diag.arg = "";
    } else if (parsed_toml.base) |base_to_parse| {
        if (options.diagnostic) |diag| diag.arg = "base";

        var keymap = try parseLayout(allocator, keyboard_layout.geometry, base_to_parse, options);
        defer keymap.deinit(allocator);

        try parseTemplate(allocator, &keyboard_layout, &keymap, Layer.base);
        try parseTemplate(allocator, &keyboard_layout, &keymap, Layer.odk);

        if (parsed_toml.altgr) |altgr_to_parse| {
            if (options.diagnostic) |diag| diag.arg = "altgr";

            var altgr_keymap = try parseLayout(allocator, keyboard_layout.geometry, altgr_to_parse, options);
            defer altgr_keymap.deinit(allocator);

            try parseTemplate(allocator, &keyboard_layout, &altgr_keymap, Layer.altgr);

            keyboard_layout.has_altgr = true;
        }

        if (options.diagnostic) |diag| diag.arg = "";
    } else {
        return ParsingError.MissingLayout;
    }

    // Spacebar
    // TODO: test with Ergo‑L if unicode char is decoded
    var spacebar_shift: ?[]const u8 = null;
    var spacebar_altgr: ?[]const u8 = null;
    var spacebar_altgr_shift: ?[]const u8 = null;
    var spacebar_odk: ?[]const u8 = null;
    var spacebar_odk_shift: ?[]const u8 = null;

    if (parsed_toml.spacebar) |spacebar_to_parse| {
        if (spacebar_to_parse.shift) |shift| {
            spacebar_shift = try arena.dupe(u8, shift);
        }
        if (spacebar_to_parse.altgr) |altgr| {
            spacebar_altgr = try arena.dupe(u8, altgr);
        }
        if (spacebar_to_parse.altgr_shift) |altgr_shift| {
            spacebar_altgr_shift = try arena.dupe(u8, altgr_shift);
        }
        if (spacebar_to_parse.@"1dk") |odk| {
            spacebar_odk = try arena.dupe(u8, odk);
        }
        if (spacebar_to_parse.@"1dk_shift") |odk_shift| {
            spacebar_odk_shift = try arena.dupe(u8, odk_shift);
        }
    }

    var layer_map = keyboard_layout.layers.getPtr(.base).?;
    try layer_map.put(arena, .spce, default_spacebar_base);

    var layer_map_shift = keyboard_layout.layers.getPtr(.shift).?;
    try layer_map_shift.put(
        arena,
        .spce,
        spacebar_shift orelse default_spacebar_shift,
    );

    if (keyboard_layout.layers.getPtr(.altgr)) |layer_map_altgr| {
        try layer_map_altgr.put(
            arena,
            .spce,
            spacebar_altgr orelse default_spacebar_altgr,
        );
    }

    if (keyboard_layout.layers.getPtr(.altgr_shift)) |layer_map_altgr_shift| {
        try layer_map_altgr_shift.put(
            arena,
            .spce,
            spacebar_altgr_shift orelse default_spacebar_altgr_shift,
        );
    }

    if (keyboard_layout.layers.getPtr(.odk)) |layer_map_odk| {
        try layer_map_odk.put(
            arena,
            .spce,
            spacebar_odk orelse default_spacebar_odk,
        );
    }

    if (keyboard_layout.layers.getPtr(.odk_shift)) |layer_map_odk_shift| {
        try layer_map_odk_shift.put(
            arena,
            .spce,
            spacebar_odk_shift orelse default_spacebar_odk_shift,
        );
    }

    // TODO: kalamine/layout.py:222 _parse_dead_keys
    // dead_keys.yaml to put in constant
    // I do dead_keys later to see how it is used and write the best data structure for the job

    // TODO: all other missing features like angle-mod

    return keyboard_layout;
}

/// Extract a keyboard layer from a template
fn parseTemplate(
    allocator: std.mem.Allocator,
    keyboard_layout: *KeyboardLayout,
    keymap: *const std.AutoHashMapUnmanaged(KeyCode, ParsedKey),
    layer: Layer,
) !void {
    const arena = keyboard_layout.arena_allocator.allocator();

    const case = try LetterCasing.init(allocator);
    defer case.deinit(allocator);

    var layer_map = keyboard_layout.layers.getPtr(layer).?;
    var layer_map_shift = keyboard_layout.layers.getPtr(layer.shifted()).?;

    var keymap_iter = keymap.iterator();

    while (keymap_iter.next()) |entry| {
        const key_code = entry.key_ptr.*;
        const parsed_key = entry.value_ptr.*;

        if (layer == .base) {
            if (parsed_key.left_up) |shift_key| {
                setOdkIfThereIs(keyboard_layout, shift_key);
                const key_to_put_shift = try arena.dupe(u8, shift_key);
                try layer_map_shift.put(arena, key_code, key_to_put_shift);

                // In the base layer, if the base character is undefined, shift prevails
                if (parsed_key.left_down == null) {
                    const key_to_put_base = try case.toLowerStr(arena, key_to_put_shift);
                    try layer_map.put(arena, key_code, key_to_put_base);
                }
            }

            if (parsed_key.left_down) |base_key| {
                setOdkIfThereIs(keyboard_layout, base_key);
                const key_to_put_base = try arena.dupe(u8, base_key);
                try layer_map.put(arena, key_code, key_to_put_base);
            }
        } else if (layer == .altgr or layer == .odk) {
            if (parsed_key.right_down) |base_key| {
                setOdkIfThereIs(keyboard_layout, base_key);
                const key_to_put_base = try arena.dupe(u8, base_key);
                try layer_map.put(arena, key_code, key_to_put_base);

                // In other layers, if the shift character is undefined, base prevails
                if (parsed_key.right_up == null) {
                    const key_to_put_shift = try case.toUpperStr(arena, key_to_put_base);
                    try layer_map_shift.put(arena, key_code, key_to_put_shift);
                }
            }

            if (parsed_key.right_up) |shift_key| {
                setOdkIfThereIs(keyboard_layout, shift_key);
                const key_to_put_shift = try arena.dupe(u8, shift_key);
                try layer_map_shift.put(arena, key_code, key_to_put_shift);
            }
        }
    }

    // TODO: kalamine/layout.py:311
    // dead_keys set
}

fn setOdkIfThereIs(keyboard_layout: *KeyboardLayout, key: []const u8) void {
    if (std.mem.eql(u8, "**", key)) {
        keyboard_layout.has_1dk = true;
    }
}

/// Extract a keyboard layout
/// Caller is responsible of freeing memory
/// Inner character memory is bound to the layout parameter
fn parseLayout(
    allocator: std.mem.Allocator,
    expected_geometry: Geometry,
    layout: []const u8,
    options: ParseOptions,
) !std.AutoHashMapUnmanaged(KeyCode, ParsedKey) {
    const graph = try Graphemes.init(allocator);
    defer graph.deinit(allocator);

    const template = expected_geometry.getTemplate();
    const keys = expected_geometry.getKeys();

    var keymap = std.AutoHashMapUnmanaged(KeyCode, ParsedKey).empty;
    errdefer keymap.deinit(allocator);

    for (keys) |row| {
        for (row.keys) |key| {
            try keymap.put(allocator, key, ParsedKey{});
        }
    }

    var template_iter = graph.iterator(template);
    var layout_iter = graph.iterator(layout);

    var line: usize = 1;
    var column: usize = 1;

    // Skip the first line return
    if (layout_iter.next()) |lc| {
        if (!std.mem.eql(u8, "\n", lc.bytes(layout))) {
            return options.setParsingError(ParsingError.WrongStructure, line, column, "\n", lc.bytes(layout));
        }
    }

    while (template_iter.next()) |tc| : (column += 1) {
        if (layout_iter.next()) |lc| {
            const template_char = tc.bytes(template);
            const layout_char = lc.bytes(layout);

            // Empty template and parsed template should have same structure
            if (!std.mem.eql(u8, template_char, " ")) {
                if (!std.mem.eql(u8, template_char, layout_char)) {
                    return options.setParsingError(ParsingError.WrongStructure, line, column, template_char, layout_char);
                }

                if (std.mem.eql(u8, template_char, "\n")) {
                    line += 1;
                    column = 0; // 0 not 1 because autoincrement at the end of iteration
                }
                continue;
            }

            const is_char_in_layout = !std.mem.eql(u8, layout_char, " ");

            const key_row = (line - 1) / nb_lines_per_key;
            if (key_row >= keys.len) {
                if (is_char_in_layout) {
                    // No layout char outside key rows
                    return options.setParsingError(ParsingError.CharAtBadPlace, line, column, "nothing", layout_char);
                } else {
                    continue;
                }
            }

            const offset = keys[key_row].offset;
            if (column <= offset) {
                if (is_char_in_layout) {
                    // No layout char in the offset
                    return options.setParsingError(ParsingError.CharAtBadPlace, line, column, "nothing", layout_char);
                } else {
                    continue;
                }
            }

            const key_column = (column - offset) / nb_columns_per_key;
            if (key_column >= keys[key_row].keys.len) {
                if (is_char_in_layout) {
                    // No layout char outside keys
                    return options.setParsingError(ParsingError.CharAtBadPlace, line, column, "nothing", layout_char);
                } else {
                    continue;
                }
            }

            const in_key_column = @mod((column - offset), nb_columns_per_key);
            if (in_key_column == 5) {
                if (is_char_in_layout) {
                    // No layout char in the 5th column of a key
                    return options.setParsingError(ParsingError.CharAtBadPlace, line, column, "nothing", layout_char);
                } else {
                    continue;
                }
            }

            if ((in_key_column == 1 or in_key_column == 3) and
                !std.mem.eql(u8, layout_char, "*"))
            {
                if (is_char_in_layout) {
                    // No other char than dead key in these columns
                    return options.setParsingError(ParsingError.CharAtBadPlace, line, column, "nothing or *", layout_char);
                } else {
                    continue;
                }
            }

            const key_code = keys[key_row].keys[key_column];
            var key = keymap.getPtr(key_code).?;

            const in_key_row = @mod((line - 1), nb_lines_per_key);
            if (in_key_row == 1) {
                // Shifted char
                try putKeyInKeymap(
                    &key.left_up,
                    &key.right_up,
                    layout_char,
                    is_char_in_layout,
                    layout,
                    lc,
                    line,
                    column,
                    in_key_column,
                    options,
                );
            } else {
                // Non-shifted char
                try putKeyInKeymap(
                    &key.left_down,
                    &key.right_down,
                    layout_char,
                    is_char_in_layout,
                    layout,
                    lc,
                    line,
                    column,
                    in_key_column,
                    options,
                );
            }
        } else {
            // Template has characters but not the layout
            return options.setParsingError(ParsingError.WrongStructure, line, column, tc.bytes(template), "nothing");
        }
    }

    // Skip the last line return
    if (layout_iter.next()) |lc| {
        if (!std.mem.eql(u8, "\n", lc.bytes(layout))) {
            return options.setParsingError(ParsingError.WrongStructure, line, column, "\n", lc.bytes(layout));
        }
        line += 1;
        column = 1;
    } else {
        return options.setParsingError(ParsingError.WrongStructure, line, column, "\n", "nothing");
    }

    if (layout_iter.next()) |lc| {
        // Layout has characters but not the template
        return options.setParsingError(ParsingError.WrongStructure, line, column, "nothing", lc.bytes(layout));
    }

    return keymap;
}

fn putKeyInKeymap(
    key_left: *?[]const u8,
    key_right: *?[]const u8,
    layout_char: []const u8,
    is_char_in_layout: bool,
    layout: []const u8,
    lc: Grapheme,
    line: usize,
    column: usize,
    in_key_column: usize,
    options: ParseOptions,
) ParsingError!void {
    switch (in_key_column) {
        1 => putKey(key_left, layout_char, is_char_in_layout),
        2 => try putKeyOrDeadKey(
            key_left,
            layout_char,
            is_char_in_layout,
            layout,
            lc,
            line,
            column,
            options,
        ),
        3 => putKey(key_right, layout_char, is_char_in_layout),
        4 => try putKeyOrDeadKey(
            key_right,
            layout_char,
            is_char_in_layout,
            layout,
            lc,
            line,
            column,
            options,
        ),
        else => unreachable,
    }
}

fn putKey(key: *?[]const u8, layout_char: []const u8, is_char_in_layout: bool) void {
    if (is_char_in_layout) {
        key.* = layout_char;
    }
}

fn putKeyOrDeadKey(
    key: *?[]const u8,
    layout_char: []const u8,
    is_char_in_layout: bool,
    layout: []const u8,
    lc: Grapheme,
    line: usize,
    column: usize,
    options: ParseOptions,
) ParsingError!void {
    if (key.*) |_| {
        if (is_char_in_layout) {
            // Dead key '*' to keep before layout char
            key.* = layout[(lc.offset - 1)..][0..(lc.len + 1)];
            // TODO: do we check here that it is a valid dead key?
            // TODO: kalamine/layout.py:311
        } else {
            // Dead key followed by a space
            return options.setParsingError(
                ParsingError.CharAtBadPlace,
                line,
                column,
                "second half of a dead key",
                layout_char,
            );
        }
    } else {
        putKey(key, layout_char, is_char_in_layout);
    }
}

const expectEqualOptionalString = @import("../test/util.zig").expectEqualOptionalString;

fn testAssertLayer(
    layer: std.AutoHashMapUnmanaged(KeyCode, []const u8),
    expected_keys: []const struct { KeyCode, []const u8 },
) !void {
    try std.testing.expectEqual(expected_keys.len, layer.size);

    for (expected_keys) |expected_key| {
        const expected_key_code, const expected_key_value = expected_key;
        const key_value = layer.get(expected_key_code);
        try expectEqualOptionalString(expected_key_value, key_value);
    }
}

test "parseKeyboardLayoutFromToml with 1dk and altgr" {
    const toml_to_parse =
        \\# kalamine keyboard layout descriptor
        \\name        = "qwerty-custom"  # full layout name, displayed in the keyboard settings
        \\name8       = "custom"         # short Windows filename: no spaces, no special chars
        \\locale      = "us"             # locale/language id
        \\variant     = "custom-variant" # layout variant id
        \\author      = "nobody"         # author name
        \\description = "custom QWERTY layout"
        \\url         = "https://OneDeadKey.github.com/kalamine"
        \\version     = "0.0.1"
        \\geometry    = "ANSI"
        \\
        \\base = '''
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
        \\'''
        \\
        \\altgr = '''
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
        \\'''
        \\
        \\[spacebar]
        \\1dk         = "'"  # apostrophe
        \\1dk_shift   = "'"  # apostrophe
        \\
    ;
    var reader = std.Io.Reader.fixed(toml_to_parse);

    var result = try parseKeyboardLayoutFromToml(std.testing.allocator, &reader, .{});
    defer result.deinit();

    try std.testing.expectEqualStrings("qwerty-custom", result.name);
    try std.testing.expectEqualStrings("custom", result.name8);
    try expectEqualOptionalString("us", result.locale);
    try expectEqualOptionalString("custom-variant", result.variant);
    try expectEqualOptionalString("nobody", result.author);
    try expectEqualOptionalString("custom QWERTY layout", result.description);
    try expectEqualOptionalString("https://OneDeadKey.github.com/kalamine", result.url);
    try expectEqualOptionalString("0.0.1", result.version);
    try std.testing.expectEqual(Geometry.ANSI, result.geometry);
    try std.testing.expect(result.has_altgr);
    try std.testing.expect(result.has_1dk);

    try std.testing.expectEqual(6, result.layers.size);

    const expected_base_layer = [_]struct { KeyCode, []const u8 }{
        .{ .tlde, "`" },
        .{ .ae01, "1" },
        .{ .ae02, "2" },
        .{ .ae03, "3" },
        .{ .ae04, "4" },
        .{ .ae05, "5" },
        .{ .ae06, "6" },
        .{ .ae07, "7" },
        .{ .ae08, "8" },
        .{ .ae09, "9" },
        .{ .ae10, "0" },
        .{ .ae11, "-" },
        .{ .ae12, "=" },

        .{ .ad01, "q" },
        .{ .ad02, "w" },
        .{ .ad03, "e" },
        .{ .ad04, "r" },
        .{ .ad05, "t" },
        .{ .ad06, "y" },
        .{ .ad07, "u" },
        .{ .ad08, "i" },
        .{ .ad09, "o" },
        .{ .ad10, "p" },
        .{ .ad11, "[" },
        .{ .ad12, "]" },

        .{ .ac01, "a" },
        .{ .ac02, "s" },
        .{ .ac03, "d" },
        .{ .ac04, "f" },
        .{ .ac05, "g" },
        .{ .ac06, "h" },
        .{ .ac07, "j" },
        .{ .ac08, "k" },
        .{ .ac09, "l" },
        .{ .ac10, ";" },
        .{ .ac11, "**" },
        .{ .bksl, "\\" },

        .{ .ab01, "z" },
        .{ .ab02, "x" },
        .{ .ab03, "c" },
        .{ .ab04, "v" },
        .{ .ab05, "b" },
        .{ .ab06, "n" },
        .{ .ab07, "m" },
        .{ .ab08, "," },
        .{ .ab09, "." },
        .{ .ab10, "/" },

        .{ .spce, " " },
    };

    try testAssertLayer(result.layers.get(.base).?, &expected_base_layer);

    const expected_shift_layer = [_]struct { KeyCode, []const u8 }{
        .{ .tlde, "~" },
        .{ .ae01, "!" },
        .{ .ae02, "@" },
        .{ .ae03, "#" },
        .{ .ae04, "$" },
        .{ .ae05, "%" },
        .{ .ae06, "^" },
        .{ .ae07, "&" },
        .{ .ae08, "*" },
        .{ .ae09, "(" },
        .{ .ae10, ")" },
        .{ .ae11, "_" },
        .{ .ae12, "+" },

        .{ .ad01, "Q" },
        .{ .ad02, "W" },
        .{ .ad03, "E" },
        .{ .ad04, "R" },
        .{ .ad05, "T" },
        .{ .ad06, "Y" },
        .{ .ad07, "U" },
        .{ .ad08, "I" },
        .{ .ad09, "O" },
        .{ .ad10, "P" },
        .{ .ad11, "{" },
        .{ .ad12, "}" },

        .{ .ac01, "A" },
        .{ .ac02, "S" },
        .{ .ac03, "D" },
        .{ .ac04, "F" },
        .{ .ac05, "G" },
        .{ .ac06, "H" },
        .{ .ac07, "J" },
        .{ .ac08, "K" },
        .{ .ac09, "L" },
        .{ .ac10, ":" },
        .{ .ac11, "*¨" },
        .{ .bksl, "|" },

        .{ .ab01, "Z" },
        .{ .ab02, "X" },
        .{ .ab03, "C" },
        .{ .ab04, "V" },
        .{ .ab05, "B" },
        .{ .ab06, "N" },
        .{ .ab07, "M" },
        .{ .ab08, "<" },
        .{ .ab09, ">" },
        .{ .ab10, "?" },

        .{ .spce, " " },
    };

    try testAssertLayer(result.layers.get(.shift).?, &expected_shift_layer);

    const expected_odk_layer = [_]struct { KeyCode, []const u8 }{
        .{ .ae02, "«" },
        .{ .ae03, "»" },
        .{ .ae05, "€" },

        .{ .ad03, "é" },
        .{ .ad06, "ý" },
        .{ .ad07, "ú" },
        .{ .ad08, "í" },
        .{ .ad09, "ó" },

        .{ .ac01, "á" },
        .{ .ac11, "'" },

        .{ .ab03, "ç" },
        .{ .ab07, "µ" },
        .{ .ab08, "·" },
        .{ .ab09, "…" },

        .{ .spce, "'" },
    };

    try testAssertLayer(result.layers.get(.odk).?, &expected_odk_layer);

    const expected_odk_shift_layer = [_]struct { KeyCode, []const u8 }{
        .{ .ae02, "«" },
        .{ .ae03, "»" },
        .{ .ae05, "€" },

        .{ .ad03, "É" },
        .{ .ad06, "Ý" },
        .{ .ad07, "Ú" },
        .{ .ad08, "Í" },
        .{ .ad09, "Ó" },

        .{ .ac01, "Á" },
        .{ .ac11, "'" },

        .{ .ab03, "Ç" },
        .{ .ab07, "Μ" },
        .{ .ab08, "•" },
        .{ .ab09, "…" },

        .{ .spce, "'" },
    };

    try testAssertLayer(result.layers.get(.odk_shift).?, &expected_odk_shift_layer);

    const expected_altgr_layer = [_]struct { KeyCode, []const u8 }{
        .{ .tlde, "*`" },
        .{ .ae06, "*^" },

        .{ .ad01, "@" },
        .{ .ad02, "<" },
        .{ .ad03, ">" },
        .{ .ad04, "$" },
        .{ .ad05, "%" },
        .{ .ad06, "^" },
        .{ .ad07, "&" },
        .{ .ad08, "*" },
        .{ .ad09, "'" },
        .{ .ad10, "`" },

        .{ .ac01, "{" },
        .{ .ac02, "(" },
        .{ .ac03, ")" },
        .{ .ac04, "}" },
        .{ .ac05, "=" },
        .{ .ac06, "\\" },
        .{ .ac07, "+" },
        .{ .ac08, "-" },
        .{ .ac09, "/" },
        .{ .ac10, "\"" },
        .{ .ac11, "*´" },

        .{ .ab01, "~" },
        .{ .ab02, "[" },
        .{ .ab03, "]" },
        .{ .ab04, "_" },
        .{ .ab05, "#" },
        .{ .ab06, "|" },
        .{ .ab07, "!" },
        .{ .ab08, ";" },
        .{ .ab09, ":" },
        .{ .ab10, "?" },

        .{ .spce, " " },
    };

    try testAssertLayer(result.layers.get(.altgr).?, &expected_altgr_layer);

    const expected_altgr_shift_layer = [_]struct { KeyCode, []const u8 }{
        .{ .tlde, "*~" },
        .{ .ae06, "*^" },

        .{ .ad01, "@" },
        .{ .ad02, "<" },
        .{ .ad03, ">" },
        .{ .ad04, "$" },
        .{ .ad05, "%" },
        .{ .ad06, "^" },
        .{ .ad07, "&" },
        .{ .ad08, "*" },
        .{ .ad09, "'" },
        .{ .ad10, "`" },

        .{ .ac01, "{" },
        .{ .ac02, "(" },
        .{ .ac03, ")" },
        .{ .ac04, "}" },
        .{ .ac05, "=" },
        .{ .ac06, "\\" },
        .{ .ac07, "+" },
        .{ .ac08, "-" },
        .{ .ac09, "/" },
        .{ .ac10, "\"" },
        .{ .ac11, "*¨" },

        .{ .ab01, "~" },
        .{ .ab02, "[" },
        .{ .ab03, "]" },
        .{ .ab04, "_" },
        .{ .ab05, "#" },
        .{ .ab06, "|" },
        .{ .ab07, "!" },
        .{ .ab08, ";" },
        .{ .ab09, ":" },
        .{ .ab10, "?" },

        .{ .spce, " " },
    };

    try testAssertLayer(result.layers.get(.altgr_shift).?, &expected_altgr_shift_layer);
}

test "parseKeyboardLayoutFromToml with 1dk" {
    const toml_to_parse =
        \\# kalamine keyboard layout descriptor
        \\name        = "qwerty-custom"  # full layout name, displayed in the keyboard settings
        \\name8       = "custom"         # short Windows filename: no spaces, no special chars
        \\locale      = "us"             # locale/language id
        \\variant     = "custom-variant" # layout variant id
        \\author      = "nobody"         # author name
        \\description = "custom QWERTY layout"
        \\url         = "https://OneDeadKey.github.com/kalamine"
        \\version     = "0.0.1"
        \\geometry    = "ANSI"
        \\
        \\base = '''
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
        \\'''
        \\
        \\[spacebar]
        \\1dk         = "'"  # apostrophe
        \\1dk_shift   = "'"  # apostrophe
        \\
    ;
    var reader = std.Io.Reader.fixed(toml_to_parse);

    var result = try parseKeyboardLayoutFromToml(std.testing.allocator, &reader, .{});
    defer result.deinit();

    try std.testing.expectEqualStrings("qwerty-custom", result.name);
    try std.testing.expectEqualStrings("custom", result.name8);
    try expectEqualOptionalString("us", result.locale);
    try expectEqualOptionalString("custom-variant", result.variant);
    try expectEqualOptionalString("nobody", result.author);
    try expectEqualOptionalString("custom QWERTY layout", result.description);
    try expectEqualOptionalString("https://OneDeadKey.github.com/kalamine", result.url);
    try expectEqualOptionalString("0.0.1", result.version);
    try std.testing.expectEqual(Geometry.ANSI, result.geometry);
    try std.testing.expect(!result.has_altgr);
    try std.testing.expect(result.has_1dk);

    try std.testing.expectEqual(6, result.layers.size);

    const expected_base_layer = [_]struct { KeyCode, []const u8 }{
        .{ .tlde, "`" },
        .{ .ae01, "1" },
        .{ .ae02, "2" },
        .{ .ae03, "3" },
        .{ .ae04, "4" },
        .{ .ae05, "5" },
        .{ .ae06, "6" },
        .{ .ae07, "7" },
        .{ .ae08, "8" },
        .{ .ae09, "9" },
        .{ .ae10, "0" },
        .{ .ae11, "-" },
        .{ .ae12, "=" },

        .{ .ad01, "q" },
        .{ .ad02, "w" },
        .{ .ad03, "e" },
        .{ .ad04, "r" },
        .{ .ad05, "t" },
        .{ .ad06, "y" },
        .{ .ad07, "u" },
        .{ .ad08, "i" },
        .{ .ad09, "o" },
        .{ .ad10, "p" },
        .{ .ad11, "[" },
        .{ .ad12, "]" },

        .{ .ac01, "a" },
        .{ .ac02, "s" },
        .{ .ac03, "d" },
        .{ .ac04, "f" },
        .{ .ac05, "g" },
        .{ .ac06, "h" },
        .{ .ac07, "j" },
        .{ .ac08, "k" },
        .{ .ac09, "l" },
        .{ .ac10, ";" },
        .{ .ac11, "**" },
        .{ .bksl, "\\" },

        .{ .ab01, "z" },
        .{ .ab02, "x" },
        .{ .ab03, "c" },
        .{ .ab04, "v" },
        .{ .ab05, "b" },
        .{ .ab06, "n" },
        .{ .ab07, "m" },
        .{ .ab08, "," },
        .{ .ab09, "." },
        .{ .ab10, "/" },

        .{ .spce, " " },
    };

    try testAssertLayer(result.layers.get(.base).?, &expected_base_layer);

    const expected_shift_layer = [_]struct { KeyCode, []const u8 }{
        .{ .tlde, "~" },
        .{ .ae01, "!" },
        .{ .ae02, "@" },
        .{ .ae03, "#" },
        .{ .ae04, "$" },
        .{ .ae05, "%" },
        .{ .ae06, "^" },
        .{ .ae07, "&" },
        .{ .ae08, "*" },
        .{ .ae09, "(" },
        .{ .ae10, ")" },
        .{ .ae11, "_" },
        .{ .ae12, "+" },

        .{ .ad01, "Q" },
        .{ .ad02, "W" },
        .{ .ad03, "E" },
        .{ .ad04, "R" },
        .{ .ad05, "T" },
        .{ .ad06, "Y" },
        .{ .ad07, "U" },
        .{ .ad08, "I" },
        .{ .ad09, "O" },
        .{ .ad10, "P" },
        .{ .ad11, "{" },
        .{ .ad12, "}" },

        .{ .ac01, "A" },
        .{ .ac02, "S" },
        .{ .ac03, "D" },
        .{ .ac04, "F" },
        .{ .ac05, "G" },
        .{ .ac06, "H" },
        .{ .ac07, "J" },
        .{ .ac08, "K" },
        .{ .ac09, "L" },
        .{ .ac10, ":" },
        .{ .ac11, "*¨" },
        .{ .bksl, "|" },

        .{ .ab01, "Z" },
        .{ .ab02, "X" },
        .{ .ab03, "C" },
        .{ .ab04, "V" },
        .{ .ab05, "B" },
        .{ .ab06, "N" },
        .{ .ab07, "M" },
        .{ .ab08, "<" },
        .{ .ab09, ">" },
        .{ .ab10, "?" },

        .{ .spce, " " },
    };

    try testAssertLayer(result.layers.get(.shift).?, &expected_shift_layer);

    const expected_odk_layer = [_]struct { KeyCode, []const u8 }{
        .{ .ae02, "«" },
        .{ .ae03, "»" },
        .{ .ae05, "€" },

        .{ .ad03, "é" },
        .{ .ad06, "ý" },
        .{ .ad07, "ú" },
        .{ .ad08, "í" },
        .{ .ad09, "ó" },

        .{ .ac01, "á" },
        .{ .ac11, "'" },

        .{ .ab03, "ç" },
        .{ .ab07, "µ" },
        .{ .ab08, "·" },
        .{ .ab09, "…" },

        .{ .spce, "'" },
    };

    try testAssertLayer(result.layers.get(.odk).?, &expected_odk_layer);

    const expected_odk_shift_layer = [_]struct { KeyCode, []const u8 }{
        .{ .ae02, "«" },
        .{ .ae03, "»" },
        .{ .ae05, "€" },

        .{ .ad03, "É" },
        .{ .ad06, "Ý" },
        .{ .ad07, "Ú" },
        .{ .ad08, "Í" },
        .{ .ad09, "Ó" },

        .{ .ac01, "Á" },
        .{ .ac11, "'" },

        .{ .ab03, "Ç" },
        .{ .ab07, "Μ" },
        .{ .ab08, "•" },
        .{ .ab09, "…" },

        .{ .spce, "'" },
    };

    try testAssertLayer(result.layers.get(.odk_shift).?, &expected_odk_shift_layer);

    const expected_altgr_layer = [_]struct { KeyCode, []const u8 }{};

    try testAssertLayer(result.layers.get(.altgr).?, &expected_altgr_layer);

    const expected_altgr_shift_layer = [_]struct { KeyCode, []const u8 }{};

    try testAssertLayer(result.layers.get(.altgr_shift).?, &expected_altgr_shift_layer);
}

test "parseKeyboardLayoutFromToml with altgr separate from base" {
    const toml_to_parse =
        \\# kalamine keyboard layout descriptor
        \\name        = "qwerty-custom"  # full layout name, displayed in the keyboard settings
        \\name8       = "custom"         # short Windows filename: no spaces, no special chars
        \\locale      = "us"             # locale/language id
        \\variant     = "custom-variant" # layout variant id
        \\author      = "nobody"         # author name
        \\description = "custom QWERTY layout"
        \\url         = "https://OneDeadKey.github.com/kalamine"
        \\version     = "0.0.1"
        \\geometry    = "ANSI"
        \\
        \\base = '''
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
        \\'''
        \\
        \\altgr = '''
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
        \\'''
        \\
    ;
    var reader = std.Io.Reader.fixed(toml_to_parse);

    var result = try parseKeyboardLayoutFromToml(std.testing.allocator, &reader, .{});
    defer result.deinit();

    try std.testing.expectEqualStrings("qwerty-custom", result.name);
    try std.testing.expectEqualStrings("custom", result.name8);
    try expectEqualOptionalString("us", result.locale);
    try expectEqualOptionalString("custom-variant", result.variant);
    try expectEqualOptionalString("nobody", result.author);
    try expectEqualOptionalString("custom QWERTY layout", result.description);
    try expectEqualOptionalString("https://OneDeadKey.github.com/kalamine", result.url);
    try expectEqualOptionalString("0.0.1", result.version);
    try std.testing.expectEqual(Geometry.ANSI, result.geometry);
    try std.testing.expect(result.has_altgr);
    try std.testing.expect(!result.has_1dk);

    try std.testing.expectEqual(6, result.layers.size);

    const expected_base_layer = [_]struct { KeyCode, []const u8 }{
        .{ .tlde, "`" },
        .{ .ae01, "1" },
        .{ .ae02, "2" },
        .{ .ae03, "3" },
        .{ .ae04, "4" },
        .{ .ae05, "5" },
        .{ .ae06, "6" },
        .{ .ae07, "7" },
        .{ .ae08, "8" },
        .{ .ae09, "9" },
        .{ .ae10, "0" },
        .{ .ae11, "-" },
        .{ .ae12, "=" },

        .{ .ad01, "q" },
        .{ .ad02, "w" },
        .{ .ad03, "e" },
        .{ .ad04, "r" },
        .{ .ad05, "t" },
        .{ .ad06, "y" },
        .{ .ad07, "u" },
        .{ .ad08, "i" },
        .{ .ad09, "o" },
        .{ .ad10, "p" },
        .{ .ad11, "[" },
        .{ .ad12, "]" },

        .{ .ac01, "a" },
        .{ .ac02, "s" },
        .{ .ac03, "d" },
        .{ .ac04, "f" },
        .{ .ac05, "g" },
        .{ .ac06, "h" },
        .{ .ac07, "j" },
        .{ .ac08, "k" },
        .{ .ac09, "l" },
        .{ .ac10, ";" },
        .{ .ac11, "'" },
        .{ .bksl, "\\" },

        .{ .ab01, "z" },
        .{ .ab02, "x" },
        .{ .ab03, "c" },
        .{ .ab04, "v" },
        .{ .ab05, "b" },
        .{ .ab06, "n" },
        .{ .ab07, "m" },
        .{ .ab08, "," },
        .{ .ab09, "." },
        .{ .ab10, "/" },

        .{ .spce, " " },
    };

    try testAssertLayer(result.layers.get(.base).?, &expected_base_layer);

    const expected_shift_layer = [_]struct { KeyCode, []const u8 }{
        .{ .tlde, "~" },
        .{ .ae01, "!" },
        .{ .ae02, "@" },
        .{ .ae03, "#" },
        .{ .ae04, "$" },
        .{ .ae05, "%" },
        .{ .ae06, "^" },
        .{ .ae07, "&" },
        .{ .ae08, "*" },
        .{ .ae09, "(" },
        .{ .ae10, ")" },
        .{ .ae11, "_" },
        .{ .ae12, "+" },

        .{ .ad01, "Q" },
        .{ .ad02, "W" },
        .{ .ad03, "E" },
        .{ .ad04, "R" },
        .{ .ad05, "T" },
        .{ .ad06, "Y" },
        .{ .ad07, "U" },
        .{ .ad08, "I" },
        .{ .ad09, "O" },
        .{ .ad10, "P" },
        .{ .ad11, "{" },
        .{ .ad12, "}" },

        .{ .ac01, "A" },
        .{ .ac02, "S" },
        .{ .ac03, "D" },
        .{ .ac04, "F" },
        .{ .ac05, "G" },
        .{ .ac06, "H" },
        .{ .ac07, "J" },
        .{ .ac08, "K" },
        .{ .ac09, "L" },
        .{ .ac10, ":" },
        .{ .ac11, "\"" },
        .{ .bksl, "|" },

        .{ .ab01, "Z" },
        .{ .ab02, "X" },
        .{ .ab03, "C" },
        .{ .ab04, "V" },
        .{ .ab05, "B" },
        .{ .ab06, "N" },
        .{ .ab07, "M" },
        .{ .ab08, "<" },
        .{ .ab09, ">" },
        .{ .ab10, "?" },

        .{ .spce, " " },
    };

    try testAssertLayer(result.layers.get(.shift).?, &expected_shift_layer);

    const expected_odk_layer = [_]struct { KeyCode, []const u8 }{};

    try testAssertLayer(result.layers.get(.odk).?, &expected_odk_layer);

    const expected_odk_shift_layer = [_]struct { KeyCode, []const u8 }{};

    try testAssertLayer(result.layers.get(.odk_shift).?, &expected_odk_shift_layer);

    const expected_altgr_layer = [_]struct { KeyCode, []const u8 }{
        .{ .tlde, "*`" },
        .{ .ae06, "*^" },

        .{ .ad01, "@" },
        .{ .ad02, "<" },
        .{ .ad03, ">" },
        .{ .ad04, "$" },
        .{ .ad05, "%" },
        .{ .ad06, "^" },
        .{ .ad07, "&" },
        .{ .ad08, "*" },
        .{ .ad09, "'" },
        .{ .ad10, "`" },

        .{ .ac01, "{" },
        .{ .ac02, "(" },
        .{ .ac03, ")" },
        .{ .ac04, "}" },
        .{ .ac05, "=" },
        .{ .ac06, "\\" },
        .{ .ac07, "+" },
        .{ .ac08, "-" },
        .{ .ac09, "/" },
        .{ .ac10, "\"" },
        .{ .ac11, "*´" },

        .{ .ab01, "~" },
        .{ .ab02, "[" },
        .{ .ab03, "]" },
        .{ .ab04, "_" },
        .{ .ab05, "#" },
        .{ .ab06, "|" },
        .{ .ab07, "!" },
        .{ .ab08, ";" },
        .{ .ab09, ":" },
        .{ .ab10, "?" },

        .{ .spce, " " },
    };

    try testAssertLayer(result.layers.get(.altgr).?, &expected_altgr_layer);

    const expected_altgr_shift_layer = [_]struct { KeyCode, []const u8 }{
        .{ .tlde, "*~" },
        .{ .ae06, "*^" },

        .{ .ad01, "@" },
        .{ .ad02, "<" },
        .{ .ad03, ">" },
        .{ .ad04, "$" },
        .{ .ad05, "%" },
        .{ .ad06, "^" },
        .{ .ad07, "&" },
        .{ .ad08, "*" },
        .{ .ad09, "'" },
        .{ .ad10, "`" },

        .{ .ac01, "{" },
        .{ .ac02, "(" },
        .{ .ac03, ")" },
        .{ .ac04, "}" },
        .{ .ac05, "=" },
        .{ .ac06, "\\" },
        .{ .ac07, "+" },
        .{ .ac08, "-" },
        .{ .ac09, "/" },
        .{ .ac10, "\"" },
        .{ .ac11, "*¨" },

        .{ .ab01, "~" },
        .{ .ab02, "[" },
        .{ .ab03, "]" },
        .{ .ab04, "_" },
        .{ .ab05, "#" },
        .{ .ab06, "|" },
        .{ .ab07, "!" },
        .{ .ab08, ";" },
        .{ .ab09, ":" },
        .{ .ab10, "?" },

        .{ .spce, " " },
    };

    try testAssertLayer(result.layers.get(.altgr_shift).?, &expected_altgr_shift_layer);
}

test "parseKeyboardLayoutFromToml with altgr on base" {
    const toml_to_parse =
        \\# kalamine keyboard layout descriptor
        \\name        = "qwerty-custom"  # full layout name, displayed in the keyboard settings
        \\name8       = "custom"         # short Windows filename: no spaces, no special chars
        \\locale      = "us"             # locale/language id
        \\variant     = "custom-variant" # layout variant id
        \\author      = "nobody"         # author name
        \\description = "custom QWERTY layout"
        \\url         = "https://OneDeadKey.github.com/kalamine"
        \\version     = "0.0.1"
        \\geometry    = "ANSI"
        \\
        \\full = '''
        \\┌─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┲━━━━━━━━━━┓
        \\│ ~*~ │ !   │ @   │ #   │ $   │ %   │ ^   │ &   │ *   │ (   │ )   │ _   │ +   ┃          ┃
        \\│ `*` │ 1   │ 2   │ 3   │ 4   │ 5   │ 6*^ │ 7   │ 8   │ 9   │ 0   │ -   │ =   ┃ ⌫        ┃
        \\┢━━━━━┷━━┱──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┺━━┯━━━━━━━┩
        \\┃        ┃ Q   │ W   │ E   │ R   │ T   │ Y   │ U   │ I   │ O   │ P   │ {   │ }   │ |     │
        \\┃ ↹      ┃   @ │   < │   > │   $ │   % │   ^ │   & │   * │   ' │   ` │ [   │ ]   │ \     │
        \\┣━━━━━━━━┻┱────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┲━━━━┷━━━━━━━┪
        \\┃         ┃ A   │ S   │ D   │ F   │ G   │ H   │ J   │ K   │ L   │ :   │ "*¨ ┃            ┃
        \\┃ ⇬       ┃   { │   ( │   ) │   } │   = │   \ │   + │   - │   / │ ; " │ '*´ ┃ ⏎          ┃
        \\┣━━━━━━━━━┻━━┱──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┲━━┻━━━━━━━━━━━━┫
        \\┃            ┃ Z   │ X   │ C   │ V   │ B   │ N   │ M   │ <   │ >   │ ?   ┃               ┃
        \\┃ ⇧          ┃   ~ │   [ │   ] │   _ │   # │   | │   ! │ , ; │ . : │ / ? ┃ ⇧             ┃
        \\┣━━━━━━━┳━━━━┻━━┳━━┷━━━━┱┴─────┴─────┴─────┴─────┴─────┴─┲━━━┷━━━┳━┷━━━━━╋━━━━━━━┳━━━━━━━┫
        \\┃       ┃       ┃       ┃                                ┃       ┃       ┃       ┃       ┃
        \\┃ Ctrl  ┃ super ┃ Alt   ┃ ␣                              ┃ Alt   ┃ super ┃ menu  ┃ Ctrl  ┃
        \\┗━━━━━━━┻━━━━━━━┻━━━━━━━┹────────────────────────────────┺━━━━━━━┻━━━━━━━┻━━━━━━━┻━━━━━━━┛
        \\'''
        \\
    ;
    var reader = std.Io.Reader.fixed(toml_to_parse);

    var result = try parseKeyboardLayoutFromToml(std.testing.allocator, &reader, .{});
    defer result.deinit();

    try std.testing.expectEqualStrings("qwerty-custom", result.name);
    try std.testing.expectEqualStrings("custom", result.name8);
    try expectEqualOptionalString("us", result.locale);
    try expectEqualOptionalString("custom-variant", result.variant);
    try expectEqualOptionalString("nobody", result.author);
    try expectEqualOptionalString("custom QWERTY layout", result.description);
    try expectEqualOptionalString("https://OneDeadKey.github.com/kalamine", result.url);
    try expectEqualOptionalString("0.0.1", result.version);
    try std.testing.expectEqual(Geometry.ANSI, result.geometry);
    try std.testing.expect(result.has_altgr);
    try std.testing.expect(!result.has_1dk);

    try std.testing.expectEqual(6, result.layers.size);

    const expected_base_layer = [_]struct { KeyCode, []const u8 }{
        .{ .tlde, "`" },
        .{ .ae01, "1" },
        .{ .ae02, "2" },
        .{ .ae03, "3" },
        .{ .ae04, "4" },
        .{ .ae05, "5" },
        .{ .ae06, "6" },
        .{ .ae07, "7" },
        .{ .ae08, "8" },
        .{ .ae09, "9" },
        .{ .ae10, "0" },
        .{ .ae11, "-" },
        .{ .ae12, "=" },

        .{ .ad01, "q" },
        .{ .ad02, "w" },
        .{ .ad03, "e" },
        .{ .ad04, "r" },
        .{ .ad05, "t" },
        .{ .ad06, "y" },
        .{ .ad07, "u" },
        .{ .ad08, "i" },
        .{ .ad09, "o" },
        .{ .ad10, "p" },
        .{ .ad11, "[" },
        .{ .ad12, "]" },

        .{ .ac01, "a" },
        .{ .ac02, "s" },
        .{ .ac03, "d" },
        .{ .ac04, "f" },
        .{ .ac05, "g" },
        .{ .ac06, "h" },
        .{ .ac07, "j" },
        .{ .ac08, "k" },
        .{ .ac09, "l" },
        .{ .ac10, ";" },
        .{ .ac11, "'" },
        .{ .bksl, "\\" },

        .{ .ab01, "z" },
        .{ .ab02, "x" },
        .{ .ab03, "c" },
        .{ .ab04, "v" },
        .{ .ab05, "b" },
        .{ .ab06, "n" },
        .{ .ab07, "m" },
        .{ .ab08, "," },
        .{ .ab09, "." },
        .{ .ab10, "/" },

        .{ .spce, " " },
    };

    try testAssertLayer(result.layers.get(.base).?, &expected_base_layer);

    const expected_shift_layer = [_]struct { KeyCode, []const u8 }{
        .{ .tlde, "~" },
        .{ .ae01, "!" },
        .{ .ae02, "@" },
        .{ .ae03, "#" },
        .{ .ae04, "$" },
        .{ .ae05, "%" },
        .{ .ae06, "^" },
        .{ .ae07, "&" },
        .{ .ae08, "*" },
        .{ .ae09, "(" },
        .{ .ae10, ")" },
        .{ .ae11, "_" },
        .{ .ae12, "+" },

        .{ .ad01, "Q" },
        .{ .ad02, "W" },
        .{ .ad03, "E" },
        .{ .ad04, "R" },
        .{ .ad05, "T" },
        .{ .ad06, "Y" },
        .{ .ad07, "U" },
        .{ .ad08, "I" },
        .{ .ad09, "O" },
        .{ .ad10, "P" },
        .{ .ad11, "{" },
        .{ .ad12, "}" },

        .{ .ac01, "A" },
        .{ .ac02, "S" },
        .{ .ac03, "D" },
        .{ .ac04, "F" },
        .{ .ac05, "G" },
        .{ .ac06, "H" },
        .{ .ac07, "J" },
        .{ .ac08, "K" },
        .{ .ac09, "L" },
        .{ .ac10, ":" },
        .{ .ac11, "\"" },
        .{ .bksl, "|" },

        .{ .ab01, "Z" },
        .{ .ab02, "X" },
        .{ .ab03, "C" },
        .{ .ab04, "V" },
        .{ .ab05, "B" },
        .{ .ab06, "N" },
        .{ .ab07, "M" },
        .{ .ab08, "<" },
        .{ .ab09, ">" },
        .{ .ab10, "?" },

        .{ .spce, " " },
    };

    try testAssertLayer(result.layers.get(.shift).?, &expected_shift_layer);

    const expected_odk_layer = [_]struct { KeyCode, []const u8 }{};

    try testAssertLayer(result.layers.get(.odk).?, &expected_odk_layer);

    const expected_odk_shift_layer = [_]struct { KeyCode, []const u8 }{};

    try testAssertLayer(result.layers.get(.odk_shift).?, &expected_odk_shift_layer);

    const expected_altgr_layer = [_]struct { KeyCode, []const u8 }{
        .{ .tlde, "*`" },
        .{ .ae06, "*^" },

        .{ .ad01, "@" },
        .{ .ad02, "<" },
        .{ .ad03, ">" },
        .{ .ad04, "$" },
        .{ .ad05, "%" },
        .{ .ad06, "^" },
        .{ .ad07, "&" },
        .{ .ad08, "*" },
        .{ .ad09, "'" },
        .{ .ad10, "`" },

        .{ .ac01, "{" },
        .{ .ac02, "(" },
        .{ .ac03, ")" },
        .{ .ac04, "}" },
        .{ .ac05, "=" },
        .{ .ac06, "\\" },
        .{ .ac07, "+" },
        .{ .ac08, "-" },
        .{ .ac09, "/" },
        .{ .ac10, "\"" },
        .{ .ac11, "*´" },

        .{ .ab01, "~" },
        .{ .ab02, "[" },
        .{ .ab03, "]" },
        .{ .ab04, "_" },
        .{ .ab05, "#" },
        .{ .ab06, "|" },
        .{ .ab07, "!" },
        .{ .ab08, ";" },
        .{ .ab09, ":" },
        .{ .ab10, "?" },

        .{ .spce, " " },
    };

    try testAssertLayer(result.layers.get(.altgr).?, &expected_altgr_layer);

    const expected_altgr_shift_layer = [_]struct { KeyCode, []const u8 }{
        .{ .tlde, "*~" },
        .{ .ae06, "*^" },

        .{ .ad01, "@" },
        .{ .ad02, "<" },
        .{ .ad03, ">" },
        .{ .ad04, "$" },
        .{ .ad05, "%" },
        .{ .ad06, "^" },
        .{ .ad07, "&" },
        .{ .ad08, "*" },
        .{ .ad09, "'" },
        .{ .ad10, "`" },

        .{ .ac01, "{" },
        .{ .ac02, "(" },
        .{ .ac03, ")" },
        .{ .ac04, "}" },
        .{ .ac05, "=" },
        .{ .ac06, "\\" },
        .{ .ac07, "+" },
        .{ .ac08, "-" },
        .{ .ac09, "/" },
        .{ .ac10, "\"" },
        .{ .ac11, "*¨" },

        .{ .ab01, "~" },
        .{ .ab02, "[" },
        .{ .ab03, "]" },
        .{ .ab04, "_" },
        .{ .ab05, "#" },
        .{ .ab06, "|" },
        .{ .ab07, "!" },
        .{ .ab08, ";" },
        .{ .ab09, ":" },
        .{ .ab10, "?" },

        .{ .spce, " " },
    };

    try testAssertLayer(result.layers.get(.altgr_shift).?, &expected_altgr_shift_layer);
}

test "parseKeyboardLayoutFromToml with base only" {
    const toml_to_parse =
        \\# kalamine keyboard layout descriptor
        \\name        = "qwerty-custom"  # full layout name, displayed in the keyboard settings
        \\name8       = "custom"         # short Windows filename: no spaces, no special chars
        \\locale      = "us"             # locale/language id
        \\variant     = "custom-variant" # layout variant id
        \\author      = "nobody"         # author name
        \\description = "custom QWERTY layout"
        \\url         = "https://OneDeadKey.github.com/kalamine"
        \\version     = "0.0.1"
        \\geometry    = "ANSI"
        \\
        \\base = '''
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
        \\'''
        \\
    ;
    var reader = std.Io.Reader.fixed(toml_to_parse);

    var result = try parseKeyboardLayoutFromToml(std.testing.allocator, &reader, .{});
    defer result.deinit();

    try std.testing.expectEqualStrings("qwerty-custom", result.name);
    try std.testing.expectEqualStrings("custom", result.name8);
    try expectEqualOptionalString("us", result.locale);
    try expectEqualOptionalString("custom-variant", result.variant);
    try expectEqualOptionalString("nobody", result.author);
    try expectEqualOptionalString("custom QWERTY layout", result.description);
    try expectEqualOptionalString("https://OneDeadKey.github.com/kalamine", result.url);
    try expectEqualOptionalString("0.0.1", result.version);
    try std.testing.expectEqual(Geometry.ANSI, result.geometry);
    try std.testing.expect(!result.has_altgr);
    try std.testing.expect(!result.has_1dk);

    try std.testing.expectEqual(6, result.layers.size);

    const expected_base_layer = [_]struct { KeyCode, []const u8 }{
        .{ .tlde, "`" },
        .{ .ae01, "1" },
        .{ .ae02, "2" },
        .{ .ae03, "3" },
        .{ .ae04, "4" },
        .{ .ae05, "5" },
        .{ .ae06, "6" },
        .{ .ae07, "7" },
        .{ .ae08, "8" },
        .{ .ae09, "9" },
        .{ .ae10, "0" },
        .{ .ae11, "-" },
        .{ .ae12, "=" },

        .{ .ad01, "q" },
        .{ .ad02, "w" },
        .{ .ad03, "e" },
        .{ .ad04, "r" },
        .{ .ad05, "t" },
        .{ .ad06, "y" },
        .{ .ad07, "u" },
        .{ .ad08, "i" },
        .{ .ad09, "o" },
        .{ .ad10, "p" },
        .{ .ad11, "[" },
        .{ .ad12, "]" },

        .{ .ac01, "a" },
        .{ .ac02, "s" },
        .{ .ac03, "d" },
        .{ .ac04, "f" },
        .{ .ac05, "g" },
        .{ .ac06, "h" },
        .{ .ac07, "j" },
        .{ .ac08, "k" },
        .{ .ac09, "l" },
        .{ .ac10, ";" },
        .{ .ac11, "'" },
        .{ .bksl, "\\" },

        .{ .ab01, "z" },
        .{ .ab02, "x" },
        .{ .ab03, "c" },
        .{ .ab04, "v" },
        .{ .ab05, "b" },
        .{ .ab06, "n" },
        .{ .ab07, "m" },
        .{ .ab08, "," },
        .{ .ab09, "." },
        .{ .ab10, "/" },

        .{ .spce, " " },
    };

    try testAssertLayer(result.layers.get(.base).?, &expected_base_layer);

    const expected_shift_layer = [_]struct { KeyCode, []const u8 }{
        .{ .tlde, "~" },
        .{ .ae01, "!" },
        .{ .ae02, "@" },
        .{ .ae03, "#" },
        .{ .ae04, "$" },
        .{ .ae05, "%" },
        .{ .ae06, "^" },
        .{ .ae07, "&" },
        .{ .ae08, "*" },
        .{ .ae09, "(" },
        .{ .ae10, ")" },
        .{ .ae11, "_" },
        .{ .ae12, "+" },

        .{ .ad01, "Q" },
        .{ .ad02, "W" },
        .{ .ad03, "E" },
        .{ .ad04, "R" },
        .{ .ad05, "T" },
        .{ .ad06, "Y" },
        .{ .ad07, "U" },
        .{ .ad08, "I" },
        .{ .ad09, "O" },
        .{ .ad10, "P" },
        .{ .ad11, "{" },
        .{ .ad12, "}" },

        .{ .ac01, "A" },
        .{ .ac02, "S" },
        .{ .ac03, "D" },
        .{ .ac04, "F" },
        .{ .ac05, "G" },
        .{ .ac06, "H" },
        .{ .ac07, "J" },
        .{ .ac08, "K" },
        .{ .ac09, "L" },
        .{ .ac10, ":" },
        .{ .ac11, "\"" },
        .{ .bksl, "|" },

        .{ .ab01, "Z" },
        .{ .ab02, "X" },
        .{ .ab03, "C" },
        .{ .ab04, "V" },
        .{ .ab05, "B" },
        .{ .ab06, "N" },
        .{ .ab07, "M" },
        .{ .ab08, "<" },
        .{ .ab09, ">" },
        .{ .ab10, "?" },

        .{ .spce, " " },
    };

    try testAssertLayer(result.layers.get(.shift).?, &expected_shift_layer);

    const expected_odk_layer = [_]struct { KeyCode, []const u8 }{};

    try testAssertLayer(result.layers.get(.odk).?, &expected_odk_layer);

    const expected_odk_shift_layer = [_]struct { KeyCode, []const u8 }{};

    try testAssertLayer(result.layers.get(.odk_shift).?, &expected_odk_shift_layer);

    const expected_altgr_layer = [_]struct { KeyCode, []const u8 }{};

    try testAssertLayer(result.layers.get(.altgr).?, &expected_altgr_layer);

    const expected_altgr_shift_layer = [_]struct { KeyCode, []const u8 }{};

    try testAssertLayer(result.layers.get(.altgr_shift).?, &expected_altgr_shift_layer);
}

test "parseLayout full layout" {
    const layout =
        \\
        \\┌─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┲━━━━━━━━━━┓
        \\│ ~   │ !   │ @   │ #   │ $   │ %   │ ^   │ &   │ *   │ (   │ )   │ _   │ +   ┃          ┃
        \\│ `   │ 1   │ 2 « │ 3 » │ 4   │ 5 € │ 6   │ 7   │ 8   │ 9   │ 0   │ -   │ =   ┃ ⌫        ┃
        \\┢━━━━━┷━━┱──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┺━━┳━━━━━━━┫
        \\┃        ┃ Q   │ W   │ E   │ R   │ T   │ Y   │ U   │ I   │ O   │ P   │ {   │ }   ┃       ┃
        \\┃ ↹      ┃     │     │   é │     │     │   ý │   ú │   í │   ó │     │ [   │ ]   ┃       ┃
        \\┣━━━━━━━━┻┱────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┺┓  ⏎   ┃
        \\┃         ┃ A   │ S   │ D   │ F   │ G   │ H   │ J   │ K   │ L   │ :   │*¨*~ │ |   ┃      ┃
        \\┃ ⇬       ┃   á │     │     │     │     │     │     │     │     │ ;   │***´ │ \   ┃      ┃
        \\┣━━━━━━┳━━┹──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┲━━┷━━━━━┻━━━━━━┫
        \\┃      ┃ |   │ Z   │ X   │ C   │ V   │ B   │ N   │ M   │ < • │ >   │ ?   ┃               ┃
        \\┃ ⇧    ┃ \   │     │     │   ç │     │     │     │   µ │ , · │ . … │ /   ┃ ⇧             ┃
        \\┣━━━━━━┻┳━━━━┷━━┳━━┷━━━━┱┴─────┴─────┴─────┴─────┴─────┴─┲━━━┷━━━┳━┷━━━━━╋━━━━━━━┳━━━━━━━┫
        \\┃       ┃       ┃       ┃                                ┃       ┃       ┃       ┃       ┃
        \\┃ Ctrl  ┃ super ┃ Alt   ┃ ␣                              ┃ AltGr ┃ super ┃ menu  ┃ Ctrl  ┃
        \\┗━━━━━━━┻━━━━━━━┻━━━━━━━┹────────────────────────────────┺━━━━━━━┻━━━━━━━┻━━━━━━━┻━━━━━━━┛
        \\
    ;

    var result = try parseLayout(std.testing.allocator, Geometry.ISO, layout, .{});
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(48, result.size);

    try std.testing.expectEqualDeep(ParsedKey{ .left_up = "~", .left_down = "`" }, result.get(.tlde));
    try std.testing.expectEqualDeep(ParsedKey{ .left_up = "!", .left_down = "1" }, result.get(.ae01));
    try std.testing.expectEqualDeep(ParsedKey{ .left_up = "@", .left_down = "2", .right_down = "«" }, result.get(.ae02));
    try std.testing.expectEqualDeep(ParsedKey{ .left_up = "#", .left_down = "3", .right_down = "»" }, result.get(.ae03));
    try std.testing.expectEqualDeep(ParsedKey{ .left_up = "$", .left_down = "4" }, result.get(.ae04));
    try std.testing.expectEqualDeep(ParsedKey{ .left_up = "%", .left_down = "5", .right_down = "€" }, result.get(.ae05));
    try std.testing.expectEqualDeep(ParsedKey{ .left_up = "^", .left_down = "6" }, result.get(.ae06));
    try std.testing.expectEqualDeep(ParsedKey{ .left_up = "&", .left_down = "7" }, result.get(.ae07));
    try std.testing.expectEqualDeep(ParsedKey{ .left_up = "*", .left_down = "8" }, result.get(.ae08));
    try std.testing.expectEqualDeep(ParsedKey{ .left_up = "(", .left_down = "9" }, result.get(.ae09));
    try std.testing.expectEqualDeep(ParsedKey{ .left_up = ")", .left_down = "0" }, result.get(.ae10));
    try std.testing.expectEqualDeep(ParsedKey{ .left_up = "_", .left_down = "-" }, result.get(.ae11));
    try std.testing.expectEqualDeep(ParsedKey{ .left_up = "+", .left_down = "=" }, result.get(.ae12));

    try std.testing.expectEqualDeep(ParsedKey{ .left_up = "Q" }, result.get(.ad01));
    try std.testing.expectEqualDeep(ParsedKey{ .left_up = "W" }, result.get(.ad02));
    try std.testing.expectEqualDeep(ParsedKey{ .left_up = "E", .right_down = "é" }, result.get(.ad03));
    try std.testing.expectEqualDeep(ParsedKey{ .left_up = "R" }, result.get(.ad04));
    try std.testing.expectEqualDeep(ParsedKey{ .left_up = "T" }, result.get(.ad05));
    try std.testing.expectEqualDeep(ParsedKey{ .left_up = "Y", .right_down = "ý" }, result.get(.ad06));
    try std.testing.expectEqualDeep(ParsedKey{ .left_up = "U", .right_down = "ú" }, result.get(.ad07));
    try std.testing.expectEqualDeep(ParsedKey{ .left_up = "I", .right_down = "í" }, result.get(.ad08));
    try std.testing.expectEqualDeep(ParsedKey{ .left_up = "O", .right_down = "ó" }, result.get(.ad09));
    try std.testing.expectEqualDeep(ParsedKey{ .left_up = "P" }, result.get(.ad10));
    try std.testing.expectEqualDeep(ParsedKey{ .left_up = "{", .left_down = "[" }, result.get(.ad11));
    try std.testing.expectEqualDeep(ParsedKey{ .left_up = "}", .left_down = "]" }, result.get(.ad12));

    try std.testing.expectEqualDeep(ParsedKey{ .left_up = "A", .right_down = "á" }, result.get(.ac01));
    try std.testing.expectEqualDeep(ParsedKey{ .left_up = "S" }, result.get(.ac02));
    try std.testing.expectEqualDeep(ParsedKey{ .left_up = "D" }, result.get(.ac03));
    try std.testing.expectEqualDeep(ParsedKey{ .left_up = "F" }, result.get(.ac04));
    try std.testing.expectEqualDeep(ParsedKey{ .left_up = "G" }, result.get(.ac05));
    try std.testing.expectEqualDeep(ParsedKey{ .left_up = "H" }, result.get(.ac06));
    try std.testing.expectEqualDeep(ParsedKey{ .left_up = "J" }, result.get(.ac07));
    try std.testing.expectEqualDeep(ParsedKey{ .left_up = "K" }, result.get(.ac08));
    try std.testing.expectEqualDeep(ParsedKey{ .left_up = "L" }, result.get(.ac09));
    try std.testing.expectEqualDeep(ParsedKey{ .left_up = ":", .left_down = ";" }, result.get(.ac10));
    try std.testing.expectEqualDeep(ParsedKey{
        .left_up = "*¨",
        .left_down = "**",
        .right_up = "*~",
        .right_down = "*´",
    }, result.get(.ac11));
    try std.testing.expectEqualDeep(ParsedKey{ .left_up = "|", .left_down = "\\" }, result.get(.bksl));

    try std.testing.expectEqualDeep(ParsedKey{ .left_up = "|", .left_down = "\\" }, result.get(.lsgt));
    try std.testing.expectEqualDeep(ParsedKey{ .left_up = "Z" }, result.get(.ab01));
    try std.testing.expectEqualDeep(ParsedKey{ .left_up = "X" }, result.get(.ab02));
    try std.testing.expectEqualDeep(ParsedKey{ .left_up = "C", .right_down = "ç" }, result.get(.ab03));
    try std.testing.expectEqualDeep(ParsedKey{ .left_up = "V" }, result.get(.ab04));
    try std.testing.expectEqualDeep(ParsedKey{ .left_up = "B" }, result.get(.ab05));
    try std.testing.expectEqualDeep(ParsedKey{ .left_up = "N" }, result.get(.ab06));
    try std.testing.expectEqualDeep(ParsedKey{ .left_up = "M", .right_down = "µ" }, result.get(.ab07));
    try std.testing.expectEqualDeep(ParsedKey{
        .left_up = "<",
        .left_down = ",",
        .right_up = "•",
        .right_down = "·",
    }, result.get(.ab08));
    try std.testing.expectEqualDeep(ParsedKey{ .left_up = ">", .left_down = ".", .right_down = "…" }, result.get(.ab09));
    try std.testing.expectEqualDeep(ParsedKey{ .left_up = "?", .left_down = "/" }, result.get(.ab10));
}

test "parseLayout half-full layout" {
    const layout =
        \\
        \\┌─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┲━━━━━━━━━━┓
        \\│ A B │ C   │ E   │     │   G │     │     │ I   │ J   │ K   │ L   │ M   │ N   ┃          ┃
        \\│ a b │   d │     │ f   │     │   h │     │     │     │     │     │     │     ┃ ⌫        ┃
        \\┢━━━━━┷━━┱──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┺━━┳━━━━━━━┫
        \\┃        ┃ O   │     │     │     │     │     │     │     │     │     │     │   P ┃       ┃
        \\┃ ↹      ┃     │     │     │     │     │     │     │     │     │     │     │     ┃       ┃
        \\┣━━━━━━━━┻┱────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┺┓  ⏎   ┃
        \\┃         ┃ Q   │     │     │     │     │     │     │     │     │     │     │   R ┃      ┃
        \\┃ ⇬       ┃     │     │     │     │     │     │     │     │     │     │     │     ┃      ┃
        \\┣━━━━━━┳━━┹──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┲━━┷━━━━━┻━━━━━━┫
        \\┃      ┃ S   │     │     │     │     │     │     │     │     │     │     ┃               ┃
        \\┃ ⇧    ┃     │     │     │     │     │     │     │     │     │     │   t ┃ ⇧             ┃
        \\┣━━━━━━┻┳━━━━┷━━┳━━┷━━━━┱┴─────┴─────┴─────┴─────┴─────┴─┲━━━┷━━━┳━┷━━━━━╋━━━━━━━┳━━━━━━━┫
        \\┃       ┃       ┃       ┃                                ┃       ┃       ┃       ┃       ┃
        \\┃ Ctrl  ┃ super ┃ Alt   ┃ ␣                              ┃ AltGr ┃ super ┃ menu  ┃ Ctrl  ┃
        \\┗━━━━━━━┻━━━━━━━┻━━━━━━━┹────────────────────────────────┺━━━━━━━┻━━━━━━━┻━━━━━━━┻━━━━━━━┛
        \\
    ;

    var result = try parseLayout(std.testing.allocator, Geometry.ISO, layout, .{});
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(48, result.size);

    try std.testing.expectEqualDeep(ParsedKey{
        .left_up = "A",
        .left_down = "a",
        .right_up = "B",
        .right_down = "b",
    }, result.get(.tlde));
    try std.testing.expectEqualDeep(ParsedKey{ .left_up = "C", .right_down = "d" }, result.get(.ae01));
    try std.testing.expectEqualDeep(ParsedKey{ .left_up = "E" }, result.get(.ae02));
    try std.testing.expectEqualDeep(ParsedKey{ .left_down = "f" }, result.get(.ae03));
    try std.testing.expectEqualDeep(ParsedKey{ .right_up = "G" }, result.get(.ae04));
    try std.testing.expectEqualDeep(ParsedKey{ .right_down = "h" }, result.get(.ae05));
    try std.testing.expectEqualDeep(ParsedKey{}, result.get(.ae06));
    try std.testing.expectEqualDeep(ParsedKey{ .left_up = "I" }, result.get(.ae07));
    try std.testing.expectEqualDeep(ParsedKey{ .left_up = "J" }, result.get(.ae08));
    try std.testing.expectEqualDeep(ParsedKey{ .left_up = "K" }, result.get(.ae09));
    try std.testing.expectEqualDeep(ParsedKey{ .left_up = "L" }, result.get(.ae10));
    try std.testing.expectEqualDeep(ParsedKey{ .left_up = "M" }, result.get(.ae11));
    try std.testing.expectEqualDeep(ParsedKey{ .left_up = "N" }, result.get(.ae12));

    try std.testing.expectEqualDeep(ParsedKey{ .left_up = "O" }, result.get(.ad01));
    try std.testing.expectEqualDeep(ParsedKey{}, result.get(.ad02));
    try std.testing.expectEqualDeep(ParsedKey{}, result.get(.ad03));
    try std.testing.expectEqualDeep(ParsedKey{}, result.get(.ad04));
    try std.testing.expectEqualDeep(ParsedKey{}, result.get(.ad05));
    try std.testing.expectEqualDeep(ParsedKey{}, result.get(.ad06));
    try std.testing.expectEqualDeep(ParsedKey{}, result.get(.ad07));
    try std.testing.expectEqualDeep(ParsedKey{}, result.get(.ad08));
    try std.testing.expectEqualDeep(ParsedKey{}, result.get(.ad09));
    try std.testing.expectEqualDeep(ParsedKey{}, result.get(.ad10));
    try std.testing.expectEqualDeep(ParsedKey{}, result.get(.ad11));
    try std.testing.expectEqualDeep(ParsedKey{ .right_up = "P" }, result.get(.ad12));

    try std.testing.expectEqualDeep(ParsedKey{ .left_up = "Q" }, result.get(.ac01));
    try std.testing.expectEqualDeep(ParsedKey{}, result.get(.ac02));
    try std.testing.expectEqualDeep(ParsedKey{}, result.get(.ac03));
    try std.testing.expectEqualDeep(ParsedKey{}, result.get(.ac04));
    try std.testing.expectEqualDeep(ParsedKey{}, result.get(.ac05));
    try std.testing.expectEqualDeep(ParsedKey{}, result.get(.ac06));
    try std.testing.expectEqualDeep(ParsedKey{}, result.get(.ac07));
    try std.testing.expectEqualDeep(ParsedKey{}, result.get(.ac08));
    try std.testing.expectEqualDeep(ParsedKey{}, result.get(.ac09));
    try std.testing.expectEqualDeep(ParsedKey{}, result.get(.ac10));
    try std.testing.expectEqualDeep(ParsedKey{}, result.get(.ac11));
    try std.testing.expectEqualDeep(ParsedKey{ .right_up = "R" }, result.get(.bksl));

    try std.testing.expectEqualDeep(ParsedKey{ .left_up = "S" }, result.get(.lsgt));
    try std.testing.expectEqualDeep(ParsedKey{}, result.get(.ab01));
    try std.testing.expectEqualDeep(ParsedKey{}, result.get(.ab02));
    try std.testing.expectEqualDeep(ParsedKey{}, result.get(.ab03));
    try std.testing.expectEqualDeep(ParsedKey{}, result.get(.ab04));
    try std.testing.expectEqualDeep(ParsedKey{}, result.get(.ab05));
    try std.testing.expectEqualDeep(ParsedKey{}, result.get(.ab06));
    try std.testing.expectEqualDeep(ParsedKey{}, result.get(.ab07));
    try std.testing.expectEqualDeep(ParsedKey{}, result.get(.ab08));
    try std.testing.expectEqualDeep(ParsedKey{}, result.get(.ab09));
    try std.testing.expectEqualDeep(ParsedKey{ .right_down = "t" }, result.get(.ab10));
}

test "parseLayout empty layout" {
    const layout =
        \\
        \\┌─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┲━━━━━━━━━━┓
        \\│     │     │     │     │     │     │     │     │     │     │     │     │     ┃          ┃
        \\│     │     │     │     │     │     │     │     │     │     │     │     │     ┃ ⌫        ┃
        \\┢━━━━━┷━━┱──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┺━━┳━━━━━━━┫
        \\┃        ┃     │     │     │     │     │     │     │     │     │     │     │     ┃       ┃
        \\┃ ↹      ┃     │     │     │     │     │     │     │     │     │     │     │     ┃       ┃
        \\┣━━━━━━━━┻┱────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┺┓  ⏎   ┃
        \\┃         ┃     │     │     │     │     │     │     │     │     │     │     │     ┃      ┃
        \\┃ ⇬       ┃     │     │     │     │     │     │     │     │     │     │     │     ┃      ┃
        \\┣━━━━━━┳━━┹──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┲━━┷━━━━━┻━━━━━━┫
        \\┃      ┃     │     │     │     │     │     │     │     │     │     │     ┃               ┃
        \\┃ ⇧    ┃     │     │     │     │     │     │     │     │     │     │     ┃ ⇧             ┃
        \\┣━━━━━━┻┳━━━━┷━━┳━━┷━━━━┱┴─────┴─────┴─────┴─────┴─────┴─┲━━━┷━━━┳━┷━━━━━╋━━━━━━━┳━━━━━━━┫
        \\┃       ┃       ┃       ┃                                ┃       ┃       ┃       ┃       ┃
        \\┃ Ctrl  ┃ super ┃ Alt   ┃ ␣                              ┃ AltGr ┃ super ┃ menu  ┃ Ctrl  ┃
        \\┗━━━━━━━┻━━━━━━━┻━━━━━━━┹────────────────────────────────┺━━━━━━━┻━━━━━━━┻━━━━━━━┻━━━━━━━┛
        \\
    ;

    var result = try parseLayout(std.testing.allocator, Geometry.ISO, layout, .{});
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(48, result.size);

    try std.testing.expectEqualDeep(ParsedKey{}, result.get(.tlde));
    try std.testing.expectEqualDeep(ParsedKey{}, result.get(.ae01));
    try std.testing.expectEqualDeep(ParsedKey{}, result.get(.ae02));
    try std.testing.expectEqualDeep(ParsedKey{}, result.get(.ae03));
    try std.testing.expectEqualDeep(ParsedKey{}, result.get(.ae04));
    try std.testing.expectEqualDeep(ParsedKey{}, result.get(.ae05));
    try std.testing.expectEqualDeep(ParsedKey{}, result.get(.ae06));
    try std.testing.expectEqualDeep(ParsedKey{}, result.get(.ae07));
    try std.testing.expectEqualDeep(ParsedKey{}, result.get(.ae08));
    try std.testing.expectEqualDeep(ParsedKey{}, result.get(.ae09));
    try std.testing.expectEqualDeep(ParsedKey{}, result.get(.ae10));
    try std.testing.expectEqualDeep(ParsedKey{}, result.get(.ae11));
    try std.testing.expectEqualDeep(ParsedKey{}, result.get(.ae12));

    try std.testing.expectEqualDeep(ParsedKey{}, result.get(.ad01));
    try std.testing.expectEqualDeep(ParsedKey{}, result.get(.ad02));
    try std.testing.expectEqualDeep(ParsedKey{}, result.get(.ad03));
    try std.testing.expectEqualDeep(ParsedKey{}, result.get(.ad04));
    try std.testing.expectEqualDeep(ParsedKey{}, result.get(.ad05));
    try std.testing.expectEqualDeep(ParsedKey{}, result.get(.ad06));
    try std.testing.expectEqualDeep(ParsedKey{}, result.get(.ad07));
    try std.testing.expectEqualDeep(ParsedKey{}, result.get(.ad08));
    try std.testing.expectEqualDeep(ParsedKey{}, result.get(.ad09));
    try std.testing.expectEqualDeep(ParsedKey{}, result.get(.ad10));
    try std.testing.expectEqualDeep(ParsedKey{}, result.get(.ad11));
    try std.testing.expectEqualDeep(ParsedKey{}, result.get(.ad12));

    try std.testing.expectEqualDeep(ParsedKey{}, result.get(.ac01));
    try std.testing.expectEqualDeep(ParsedKey{}, result.get(.ac02));
    try std.testing.expectEqualDeep(ParsedKey{}, result.get(.ac03));
    try std.testing.expectEqualDeep(ParsedKey{}, result.get(.ac04));
    try std.testing.expectEqualDeep(ParsedKey{}, result.get(.ac05));
    try std.testing.expectEqualDeep(ParsedKey{}, result.get(.ac06));
    try std.testing.expectEqualDeep(ParsedKey{}, result.get(.ac07));
    try std.testing.expectEqualDeep(ParsedKey{}, result.get(.ac08));
    try std.testing.expectEqualDeep(ParsedKey{}, result.get(.ac09));
    try std.testing.expectEqualDeep(ParsedKey{}, result.get(.ac10));
    try std.testing.expectEqualDeep(ParsedKey{}, result.get(.ac11));
    try std.testing.expectEqualDeep(ParsedKey{}, result.get(.bksl));

    try std.testing.expectEqualDeep(ParsedKey{}, result.get(.lsgt));
    try std.testing.expectEqualDeep(ParsedKey{}, result.get(.ab01));
    try std.testing.expectEqualDeep(ParsedKey{}, result.get(.ab02));
    try std.testing.expectEqualDeep(ParsedKey{}, result.get(.ab03));
    try std.testing.expectEqualDeep(ParsedKey{}, result.get(.ab04));
    try std.testing.expectEqualDeep(ParsedKey{}, result.get(.ab05));
    try std.testing.expectEqualDeep(ParsedKey{}, result.get(.ab06));
    try std.testing.expectEqualDeep(ParsedKey{}, result.get(.ab07));
    try std.testing.expectEqualDeep(ParsedKey{}, result.get(.ab08));
    try std.testing.expectEqualDeep(ParsedKey{}, result.get(.ab09));
    try std.testing.expectEqualDeep(ParsedKey{}, result.get(.ab10));
}

test "parseLayout no first line return" {
    const layout =
        \\┌─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┲━━━━━━━━━━┓
        \\│     │     │     │     │     │     │     │     │     │     │     │     │     ┃          ┃
        \\│     │     │     │     │     │     │     │     │     │     │     │     │     ┃ ⌫        ┃
        \\┢━━━━━┷━━┱──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┺━━┳━━━━━━━┫
        \\┃        ┃     │     │     │     │     │     │     │     │     │     │     │     ┃       ┃
        \\┃ ↹      ┃     │     │     │     │     │     │     │     │     │     │     │     ┃       ┃
        \\┣━━━━━━━━┻┱────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┺┓  ⏎   ┃
        \\┃         ┃     │     │     │     │     │     │     │     │     │     │     │     ┃      ┃
        \\┃ ⇬       ┃     │     │     │     │     │     │     │     │     │     │     │     ┃      ┃
        \\┣━━━━━━┳━━┹──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┲━━┷━━━━━┻━━━━━━┫
        \\┃      ┃     │     │     │     │     │     │     │     │     │     │     ┃               ┃
        \\┃ ⇧    ┃     │     │     │     │     │     │     │     │     │     │     ┃ ⇧             ┃
        \\┣━━━━━━┻┳━━━━┷━━┳━━┷━━━━┱┴─────┴─────┴─────┴─────┴─────┴─┲━━━┷━━━┳━┷━━━━━╋━━━━━━━┳━━━━━━━┫
        \\┃       ┃       ┃       ┃                                ┃       ┃       ┃       ┃       ┃
        \\┃ Ctrl  ┃ super ┃ Alt   ┃ ␣                              ┃ AltGr ┃ super ┃ menu  ┃ Ctrl  ┃
        \\┗━━━━━━━┻━━━━━━━┻━━━━━━━┹────────────────────────────────┺━━━━━━━┻━━━━━━━┻━━━━━━━┻━━━━━━━┛
        \\
    ;

    var diag = Diagnostic{ .allocator = std.testing.allocator };
    defer diag.deinit();

    const result = parseLayout(std.testing.allocator, Geometry.ISO, layout, .{ .diagnostic = &diag });

    try std.testing.expectEqual(ParsingError.WrongStructure, result);
    try std.testing.expectEqual(1, diag.line);
    try std.testing.expectEqual(1, diag.column);
    try expectEqualOptionalString("a line return", diag.expected);
    try expectEqualOptionalString("┌", diag.found);
}

test "parseLayout no last line return" {
    const layout =
        \\
        \\┌─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┲━━━━━━━━━━┓
        \\│     │     │     │     │     │     │     │     │     │     │     │     │     ┃          ┃
        \\│     │     │     │     │     │     │     │     │     │     │     │     │     ┃ ⌫        ┃
        \\┢━━━━━┷━━┱──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┺━━┳━━━━━━━┫
        \\┃        ┃     │     │     │     │     │     │     │     │     │     │     │     ┃       ┃
        \\┃ ↹      ┃     │     │     │     │     │     │     │     │     │     │     │     ┃       ┃
        \\┣━━━━━━━━┻┱────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┺┓  ⏎   ┃
        \\┃         ┃     │     │     │     │     │     │     │     │     │     │     │     ┃      ┃
        \\┃ ⇬       ┃     │     │     │     │     │     │     │     │     │     │     │     ┃      ┃
        \\┣━━━━━━┳━━┹──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┲━━┷━━━━━┻━━━━━━┫
        \\┃      ┃     │     │     │     │     │     │     │     │     │     │     ┃               ┃
        \\┃ ⇧    ┃     │     │     │     │     │     │     │     │     │     │     ┃ ⇧             ┃
        \\┣━━━━━━┻┳━━━━┷━━┳━━┷━━━━┱┴─────┴─────┴─────┴─────┴─────┴─┲━━━┷━━━┳━┷━━━━━╋━━━━━━━┳━━━━━━━┫
        \\┃       ┃       ┃       ┃                                ┃       ┃       ┃       ┃       ┃
        \\┃ Ctrl  ┃ super ┃ Alt   ┃ ␣                              ┃ AltGr ┃ super ┃ menu  ┃ Ctrl  ┃
        \\┗━━━━━━━┻━━━━━━━┻━━━━━━━┹────────────────────────────────┺━━━━━━━┻━━━━━━━┻━━━━━━━┻━━━━━━━┛
    ;

    var diag = Diagnostic{ .allocator = std.testing.allocator };
    defer diag.deinit();

    const result = parseLayout(std.testing.allocator, Geometry.ISO, layout, .{ .diagnostic = &diag });

    try std.testing.expectEqual(ParsingError.WrongStructure, result);
    try std.testing.expectEqual(16, diag.line);
    try std.testing.expectEqual(91, diag.column);
    try expectEqualOptionalString("a line return", diag.expected);
    try expectEqualOptionalString("nothing", diag.found);
}

test "parseLayout truncated layout" {
    const layout =
        \\
        \\┌─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┲━━━━━━━━━━┓
        \\
    ;

    var diag = Diagnostic{ .allocator = std.testing.allocator };
    defer diag.deinit();

    const result = parseLayout(std.testing.allocator, Geometry.ISO, layout, .{ .diagnostic = &diag });

    try std.testing.expectEqual(ParsingError.WrongStructure, result);
    try std.testing.expectEqual(2, diag.line);
    try std.testing.expectEqual(1, diag.column);
    try expectEqualOptionalString("│", diag.expected);
    try expectEqualOptionalString("nothing", diag.found);
}

test "parseLayout truncated layout line return" {
    const layout =
        \\
        \\┌─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┲━━━━━━━━━━┓
    ;

    var diag = Diagnostic{ .allocator = std.testing.allocator };
    defer diag.deinit();

    const result = parseLayout(std.testing.allocator, Geometry.ISO, layout, .{ .diagnostic = &diag });

    try std.testing.expectEqual(ParsingError.WrongStructure, result);
    try std.testing.expectEqual(1, diag.line);
    try std.testing.expectEqual(91, diag.column);
    try expectEqualOptionalString("a line return", diag.expected);
    try expectEqualOptionalString("nothing", diag.found);
}

test "parseLayout too many char" {
    const layout =
        \\
        \\┌─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┲━━━━━━━━━━┓
        \\│     │     │     │     │     │     │     │     │     │     │     │     │     ┃          ┃
        \\│     │     │     │     │     │     │     │     │     │     │     │     │     ┃ ⌫        ┃
        \\┢━━━━━┷━━┱──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┺━━┳━━━━━━━┫
        \\┃        ┃     │     │     │     │     │     │     │     │     │     │     │     ┃       ┃
        \\┃ ↹      ┃     │     │     │     │     │     │     │     │     │     │     │     ┃       ┃
        \\┣━━━━━━━━┻┱────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┺┓  ⏎   ┃
        \\┃         ┃     │     │     │     │     │     │     │     │     │     │     │     ┃      ┃
        \\┃ ⇬       ┃     │     │     │     │     │     │     │     │     │     │     │     ┃      ┃
        \\┣━━━━━━┳━━┹──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┲━━┷━━━━━┻━━━━━━┫
        \\┃      ┃     │     │     │     │     │     │     │     │     │     │     ┃               ┃
        \\┃ ⇧    ┃     │     │     │     │     │     │     │     │     │     │     ┃ ⇧             ┃
        \\┣━━━━━━┻┳━━━━┷━━┳━━┷━━━━┱┴─────┴─────┴─────┴─────┴─────┴─┲━━━┷━━━┳━┷━━━━━╋━━━━━━━┳━━━━━━━┫
        \\┃       ┃       ┃       ┃                                ┃       ┃       ┃       ┃       ┃
        \\┃ Ctrl  ┃ super ┃ Alt   ┃ ␣                              ┃ AltGr ┃ super ┃ menu  ┃ Ctrl  ┃
        \\┗━━━━━━━┻━━━━━━━┻━━━━━━━┹────────────────────────────────┺━━━━━━━┻━━━━━━━┻━━━━━━━┻━━━━━━━┛
        \\a
    ;

    var diag = Diagnostic{ .allocator = std.testing.allocator };
    defer diag.deinit();

    const result = parseLayout(std.testing.allocator, Geometry.ISO, layout, .{ .diagnostic = &diag });

    try std.testing.expectEqual(ParsingError.WrongStructure, result);
    try std.testing.expectEqual(17, diag.line);
    try std.testing.expectEqual(1, diag.column);
    try expectEqualOptionalString("nothing", diag.expected);
    try expectEqualOptionalString("a", diag.found);
}

test "parseLayout too many line returns" {
    const layout =
        \\
        \\┌─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┲━━━━━━━━━━┓
        \\│     │     │     │     │     │     │     │     │     │     │     │     │     ┃          ┃
        \\│     │     │     │     │     │     │     │     │     │     │     │     │     ┃ ⌫        ┃
        \\┢━━━━━┷━━┱──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┺━━┳━━━━━━━┫
        \\┃        ┃     │     │     │     │     │     │     │     │     │     │     │     ┃       ┃
        \\┃ ↹      ┃     │     │     │     │     │     │     │     │     │     │     │     ┃       ┃
        \\┣━━━━━━━━┻┱────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┺┓  ⏎   ┃
        \\┃         ┃     │     │     │     │     │     │     │     │     │     │     │     ┃      ┃
        \\┃ ⇬       ┃     │     │     │     │     │     │     │     │     │     │     │     ┃      ┃
        \\┣━━━━━━┳━━┹──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┲━━┷━━━━━┻━━━━━━┫
        \\┃      ┃     │     │     │     │     │     │     │     │     │     │     ┃               ┃
        \\┃ ⇧    ┃     │     │     │     │     │     │     │     │     │     │     ┃ ⇧             ┃
        \\┣━━━━━━┻┳━━━━┷━━┳━━┷━━━━┱┴─────┴─────┴─────┴─────┴─────┴─┲━━━┷━━━┳━┷━━━━━╋━━━━━━━┳━━━━━━━┫
        \\┃       ┃       ┃       ┃                                ┃       ┃       ┃       ┃       ┃
        \\┃ Ctrl  ┃ super ┃ Alt   ┃ ␣                              ┃ AltGr ┃ super ┃ menu  ┃ Ctrl  ┃
        \\┗━━━━━━━┻━━━━━━━┻━━━━━━━┹────────────────────────────────┺━━━━━━━┻━━━━━━━┻━━━━━━━┻━━━━━━━┛
        \\
        \\
    ;

    var diag = Diagnostic{ .allocator = std.testing.allocator };
    defer diag.deinit();

    const result = parseLayout(std.testing.allocator, Geometry.ISO, layout, .{ .diagnostic = &diag });

    try std.testing.expectEqual(ParsingError.WrongStructure, result);
    try std.testing.expectEqual(17, diag.line);
    try std.testing.expectEqual(1, diag.column);
    try expectEqualOptionalString("nothing", diag.expected);
    try expectEqualOptionalString("a line return", diag.found);
}

test "parseLayout wrong indentation with spaces" {
    const layout =
        \\
        \\  ┌─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┲━━━━━━━━━━┓
        \\  │     │     │     │     │     │     │     │     │     │     │     │     │     ┃          ┃
        \\  │     │     │     │     │     │     │     │     │     │     │     │     │     ┃ ⌫        ┃
        \\  ┢━━━━━┷━━┱──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┺━━┳━━━━━━━┫
        \\  ┃        ┃     │     │     │     │     │     │     │     │     │     │     │     ┃       ┃
        \\  ┃ ↹      ┃     │     │     │     │     │     │     │     │     │     │     │     ┃       ┃
        \\  ┣━━━━━━━━┻┱────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┺┓  ⏎   ┃
        \\  ┃         ┃     │     │     │     │     │     │     │     │     │     │     │     ┃      ┃
        \\  ┃ ⇬       ┃     │     │     │     │     │     │     │     │     │     │     │     ┃      ┃
        \\  ┣━━━━━━┳━━┹──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┲━━┷━━━━━┻━━━━━━┫
        \\  ┃      ┃     │     │     │     │     │     │     │     │     │     │     ┃               ┃
        \\  ┃ ⇧    ┃     │     │     │     │     │     │     │     │     │     │     ┃ ⇧             ┃
        \\  ┣━━━━━━┻┳━━━━┷━━┳━━┷━━━━┱┴─────┴─────┴─────┴─────┴─────┴─┲━━━┷━━━┳━┷━━━━━╋━━━━━━━┳━━━━━━━┫
        \\  ┃       ┃       ┃       ┃                                ┃       ┃       ┃       ┃       ┃
        \\  ┃ Ctrl  ┃ super ┃ Alt   ┃ ␣                              ┃ AltGr ┃ super ┃ menu  ┃ Ctrl  ┃
        \\  ┗━━━━━━━┻━━━━━━━┻━━━━━━━┹────────────────────────────────┺━━━━━━━┻━━━━━━━┻━━━━━━━┻━━━━━━━┛
        \\
    ;

    var diag = Diagnostic{ .allocator = std.testing.allocator };
    defer diag.deinit();

    const result = parseLayout(std.testing.allocator, Geometry.ISO, layout, .{ .diagnostic = &diag });

    try std.testing.expectEqual(ParsingError.WrongStructure, result);
    try std.testing.expectEqual(1, diag.line);
    try std.testing.expectEqual(1, diag.column);
    try expectEqualOptionalString("┌", diag.expected);
    try expectEqualOptionalString("a space", diag.found);
}

test "parseLayout wrong indentation with tab" {
    const layout = "\n\t┌─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┲━━━━━━━━━━┓";

    var diag = Diagnostic{ .allocator = std.testing.allocator };
    defer diag.deinit();

    const result = parseLayout(std.testing.allocator, Geometry.ISO, layout, .{ .diagnostic = &diag });

    try std.testing.expectEqual(ParsingError.WrongStructure, result);
    try std.testing.expectEqual(1, diag.line);
    try std.testing.expectEqual(1, diag.column);
    try expectEqualOptionalString("┌", diag.expected);
    try expectEqualOptionalString("a tabulation", diag.found);
}

test "parseLayout should not have char in offset" {
    const layout =
        \\
        \\┌─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┲━━━━━━━━━━┓
        \\│     │     │     │     │     │     │     │     │     │     │     │     │     ┃          ┃
        \\│     │     │     │     │     │     │     │     │     │     │     │     │     ┃ ⌫        ┃
        \\┢━━━━━┷━━┱──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┺━━┳━━━━━━━┫
        \\┃        ┃     │     │     │     │     │     │     │     │     │     │     │     ┃       ┃
        \\┃ ↹   a  ┃     │     │     │     │     │     │     │     │     │     │     │     ┃       ┃
        \\┣━━━━━━━━┻┱────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┺┓  ⏎   ┃
        \\┃         ┃     │     │     │     │     │     │     │     │     │     │     │     ┃      ┃
        \\┃ ⇬       ┃     │     │     │     │     │     │     │     │     │     │     │     ┃      ┃
        \\┣━━━━━━┳━━┹──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┲━━┷━━━━━┻━━━━━━┫
        \\┃      ┃     │     │     │     │     │     │     │     │     │     │     ┃               ┃
        \\┃ ⇧    ┃     │     │     │     │     │     │     │     │     │     │     ┃ ⇧             ┃
        \\┣━━━━━━┻┳━━━━┷━━┳━━┷━━━━┱┴─────┴─────┴─────┴─────┴─────┴─┲━━━┷━━━┳━┷━━━━━╋━━━━━━━┳━━━━━━━┫
        \\┃       ┃       ┃       ┃                                ┃       ┃       ┃       ┃       ┃
        \\┃ Ctrl  ┃ super ┃ Alt   ┃ ␣                              ┃ AltGr ┃ super ┃ menu  ┃ Ctrl  ┃
        \\┗━━━━━━━┻━━━━━━━┻━━━━━━━┹────────────────────────────────┺━━━━━━━┻━━━━━━━┻━━━━━━━┻━━━━━━━┛
        \\
    ;

    var diag = Diagnostic{ .allocator = std.testing.allocator };
    defer diag.deinit();

    const result = parseLayout(std.testing.allocator, Geometry.ISO, layout, .{ .diagnostic = &diag });

    try std.testing.expectEqual(ParsingError.CharAtBadPlace, result);
    try std.testing.expectEqual(6, diag.line);
    try std.testing.expectEqual(7, diag.column);
    try expectEqualOptionalString("nothing", diag.expected);
    try expectEqualOptionalString("a", diag.found);
}

test "parseLayout should not have char after keys" {
    const layout =
        \\
        \\┌─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┲━━━━━━━━━━┓
        \\│     │     │     │     │     │     │     │     │     │     │     │     │     ┃          ┃
        \\│     │     │     │     │     │     │     │     │     │     │     │     │     ┃ ⌫        ┃
        \\┢━━━━━┷━━┱──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┺━━┳━━━━━━━┫
        \\┃        ┃     │     │     │     │     │     │     │     │     │     │     │     ┃       ┃
        \\┃ ↹      ┃     │     │     │     │     │     │     │     │     │     │     │     ┃   a   ┃
        \\┣━━━━━━━━┻┱────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┺┓  ⏎   ┃
        \\┃         ┃     │     │     │     │     │     │     │     │     │     │     │     ┃      ┃
        \\┃ ⇬       ┃     │     │     │     │     │     │     │     │     │     │     │     ┃      ┃
        \\┣━━━━━━┳━━┹──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┲━━┷━━━━━┻━━━━━━┫
        \\┃      ┃     │     │     │     │     │     │     │     │     │     │     ┃               ┃
        \\┃ ⇧    ┃     │     │     │     │     │     │     │     │     │     │     ┃ ⇧             ┃
        \\┣━━━━━━┻┳━━━━┷━━┳━━┷━━━━┱┴─────┴─────┴─────┴─────┴─────┴─┲━━━┷━━━┳━┷━━━━━╋━━━━━━━┳━━━━━━━┫
        \\┃       ┃       ┃       ┃                                ┃       ┃       ┃       ┃       ┃
        \\┃ Ctrl  ┃ super ┃ Alt   ┃ ␣                              ┃ AltGr ┃ super ┃ menu  ┃ Ctrl  ┃
        \\┗━━━━━━━┻━━━━━━━┻━━━━━━━┹────────────────────────────────┺━━━━━━━┻━━━━━━━┻━━━━━━━┻━━━━━━━┛
        \\
    ;

    var diag = Diagnostic{ .allocator = std.testing.allocator };
    defer diag.deinit();

    const result = parseLayout(std.testing.allocator, Geometry.ISO, layout, .{ .diagnostic = &diag });

    try std.testing.expectEqual(ParsingError.CharAtBadPlace, result);
    try std.testing.expectEqual(6, diag.line);
    try std.testing.expectEqual(86, diag.column);
    try expectEqualOptionalString("nothing", diag.expected);
    try expectEqualOptionalString("a", diag.found);
}

test "parseLayout should not have char in last line" {
    const layout =
        \\
        \\┌─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┲━━━━━━━━━━┓
        \\│     │     │     │     │     │     │     │     │     │     │     │     │     ┃          ┃
        \\│     │     │     │     │     │     │     │     │     │     │     │     │     ┃ ⌫        ┃
        \\┢━━━━━┷━━┱──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┺━━┳━━━━━━━┫
        \\┃        ┃     │     │     │     │     │     │     │     │     │     │     │     ┃       ┃
        \\┃ ↹      ┃     │     │     │     │     │     │     │     │     │     │     │     ┃       ┃
        \\┣━━━━━━━━┻┱────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┺┓  ⏎   ┃
        \\┃         ┃     │     │     │     │     │     │     │     │     │     │     │     ┃      ┃
        \\┃ ⇬       ┃     │     │     │     │     │     │     │     │     │     │     │     ┃      ┃
        \\┣━━━━━━┳━━┹──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┲━━┷━━━━━┻━━━━━━┫
        \\┃      ┃     │     │     │     │     │     │     │     │     │     │     ┃               ┃
        \\┃ ⇧    ┃     │     │     │     │     │     │     │     │     │     │     ┃ ⇧             ┃
        \\┣━━━━━━┻┳━━━━┷━━┳━━┷━━━━┱┴─────┴─────┴─────┴─────┴─────┴─┲━━━┷━━━┳━┷━━━━━╋━━━━━━━┳━━━━━━━┫
        \\┃       ┃       ┃       ┃                                ┃       ┃       ┃       ┃       ┃
        \\┃ Ctrl  ┃ super ┃ Alt   ┃ ␣             a                ┃ AltGr ┃ super ┃ menu  ┃ Ctrl  ┃
        \\┗━━━━━━━┻━━━━━━━┻━━━━━━━┹────────────────────────────────┺━━━━━━━┻━━━━━━━┻━━━━━━━┻━━━━━━━┛
        \\
    ;

    var diag = Diagnostic{ .allocator = std.testing.allocator };
    defer diag.deinit();

    const result = parseLayout(std.testing.allocator, Geometry.ISO, layout, .{ .diagnostic = &diag });

    try std.testing.expectEqual(ParsingError.CharAtBadPlace, result);
    try std.testing.expectEqual(15, diag.line);
    try std.testing.expectEqual(41, diag.column);
    try expectEqualOptionalString("nothing", diag.expected);
    try expectEqualOptionalString("a", diag.found);
}

test "parseLayout should not have char in last column of a key" {
    const layout =
        \\
        \\┌─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┲━━━━━━━━━━┓
        \\│     │     │     │     │     │     │     │     │     │     │     │     │     ┃          ┃
        \\│     │     │     │     │     │     │    a│     │     │     │     │     │     ┃ ⌫        ┃
        \\┢━━━━━┷━━┱──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┺━━┳━━━━━━━┫
        \\┃        ┃     │     │     │     │     │     │     │     │     │     │     │     ┃       ┃
        \\┃ ↹      ┃     │     │     │     │     │     │     │     │     │     │     │     ┃       ┃
        \\┣━━━━━━━━┻┱────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┺┓  ⏎   ┃
        \\┃         ┃     │     │     │     │     │     │     │     │     │     │     │     ┃      ┃
        \\┃ ⇬       ┃     │     │     │     │     │     │     │     │     │     │     │     ┃      ┃
        \\┣━━━━━━┳━━┹──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┲━━┷━━━━━┻━━━━━━┫
        \\┃      ┃     │     │     │     │     │     │     │     │     │     │     ┃               ┃
        \\┃ ⇧    ┃     │     │     │     │     │     │     │     │     │     │     ┃ ⇧             ┃
        \\┣━━━━━━┻┳━━━━┷━━┳━━┷━━━━┱┴─────┴─────┴─────┴─────┴─────┴─┲━━━┷━━━┳━┷━━━━━╋━━━━━━━┳━━━━━━━┫
        \\┃       ┃       ┃       ┃                                ┃       ┃       ┃       ┃       ┃
        \\┃ Ctrl  ┃ super ┃ Alt   ┃ ␣                              ┃ AltGr ┃ super ┃ menu  ┃ Ctrl  ┃
        \\┗━━━━━━━┻━━━━━━━┻━━━━━━━┹────────────────────────────────┺━━━━━━━┻━━━━━━━┻━━━━━━━┻━━━━━━━┛
        \\
    ;

    var diag = Diagnostic{ .allocator = std.testing.allocator };
    defer diag.deinit();

    const result = parseLayout(std.testing.allocator, Geometry.ISO, layout, .{ .diagnostic = &diag });

    try std.testing.expectEqual(ParsingError.CharAtBadPlace, result);
    try std.testing.expectEqual(3, diag.line);
    try std.testing.expectEqual(42, diag.column);
    try expectEqualOptionalString("nothing", diag.expected);
    try expectEqualOptionalString("a", diag.found);
}

test "parseLayout should not have char in 1st column of a key" {
    const layout =
        \\
        \\┌─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┲━━━━━━━━━━┓
        \\│     │     │     │     │     │     │     │     │     │     │     │     │     ┃          ┃
        \\│     │     │     │     │     │     │     │     │     │     │     │     │     ┃ ⌫        ┃
        \\┢━━━━━┷━━┱──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┺━━┳━━━━━━━┫
        \\┃        ┃     │     │     │     │     │a    │     │     │     │     │     │     ┃       ┃
        \\┃ ↹      ┃     │     │     │     │     │     │     │     │     │     │     │     ┃       ┃
        \\┣━━━━━━━━┻┱────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┺┓  ⏎   ┃
        \\┃         ┃     │     │     │     │     │     │     │     │     │     │     │     ┃      ┃
        \\┃ ⇬       ┃     │     │     │     │     │     │     │     │     │     │     │     ┃      ┃
        \\┣━━━━━━┳━━┹──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┲━━┷━━━━━┻━━━━━━┫
        \\┃      ┃     │     │     │     │     │     │     │     │     │     │     ┃               ┃
        \\┃ ⇧    ┃     │     │     │     │     │     │     │     │     │     │     ┃ ⇧             ┃
        \\┣━━━━━━┻┳━━━━┷━━┳━━┷━━━━┱┴─────┴─────┴─────┴─────┴─────┴─┲━━━┷━━━┳━┷━━━━━╋━━━━━━━┳━━━━━━━┫
        \\┃       ┃       ┃       ┃                                ┃       ┃       ┃       ┃       ┃
        \\┃ Ctrl  ┃ super ┃ Alt   ┃ ␣                              ┃ AltGr ┃ super ┃ menu  ┃ Ctrl  ┃
        \\┗━━━━━━━┻━━━━━━━┻━━━━━━━┹────────────────────────────────┺━━━━━━━┻━━━━━━━┻━━━━━━━┻━━━━━━━┛
        \\
    ;

    var diag = Diagnostic{ .allocator = std.testing.allocator };
    defer diag.deinit();

    const result = parseLayout(std.testing.allocator, Geometry.ISO, layout, .{ .diagnostic = &diag });

    try std.testing.expectEqual(ParsingError.CharAtBadPlace, result);
    try std.testing.expectEqual(5, diag.line);
    try std.testing.expectEqual(41, diag.column);
    try expectEqualOptionalString("nothing or *", diag.expected);
    try expectEqualOptionalString("a", diag.found);
}

test "parseLayout should not have char in 3rd column of a key" {
    const layout =
        \\
        \\┌─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┲━━━━━━━━━━┓
        \\│     │     │     │     │     │     │     │     │     │     │     │     │     ┃          ┃
        \\│     │     │     │     │     │     │     │     │     │     │     │     │     ┃ ⌫        ┃
        \\┢━━━━━┷━━┱──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┺━━┳━━━━━━━┫
        \\┃        ┃     │     │     │     │     │  a  │     │     │     │     │     │     ┃       ┃
        \\┃ ↹      ┃     │     │     │     │     │     │     │     │     │     │     │     ┃       ┃
        \\┣━━━━━━━━┻┱────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┺┓  ⏎   ┃
        \\┃         ┃     │     │     │     │     │     │     │     │     │     │     │     ┃      ┃
        \\┃ ⇬       ┃     │     │     │     │     │     │     │     │     │     │     │     ┃      ┃
        \\┣━━━━━━┳━━┹──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┲━━┷━━━━━┻━━━━━━┫
        \\┃      ┃     │     │     │     │     │     │     │     │     │     │     ┃               ┃
        \\┃ ⇧    ┃     │     │     │     │     │     │     │     │     │     │     ┃ ⇧             ┃
        \\┣━━━━━━┻┳━━━━┷━━┳━━┷━━━━┱┴─────┴─────┴─────┴─────┴─────┴─┲━━━┷━━━┳━┷━━━━━╋━━━━━━━┳━━━━━━━┫
        \\┃       ┃       ┃       ┃                                ┃       ┃       ┃       ┃       ┃
        \\┃ Ctrl  ┃ super ┃ Alt   ┃ ␣                              ┃ AltGr ┃ super ┃ menu  ┃ Ctrl  ┃
        \\┗━━━━━━━┻━━━━━━━┻━━━━━━━┹────────────────────────────────┺━━━━━━━┻━━━━━━━┻━━━━━━━┻━━━━━━━┛
        \\
    ;

    var diag = Diagnostic{ .allocator = std.testing.allocator };
    defer diag.deinit();

    const result = parseLayout(std.testing.allocator, Geometry.ISO, layout, .{ .diagnostic = &diag });

    try std.testing.expectEqual(ParsingError.CharAtBadPlace, result);
    try std.testing.expectEqual(5, diag.line);
    try std.testing.expectEqual(43, diag.column);
    try expectEqualOptionalString("nothing or *", diag.expected);
    try expectEqualOptionalString("a", diag.found);
}

test "parseLayout empty dead key" {
    const layout =
        \\
        \\┌─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┲━━━━━━━━━━┓
        \\│*    │     │     │     │     │     │     │     │     │     │     │     │     ┃          ┃
        \\│     │     │     │     │     │     │     │     │     │     │     │     │     ┃ ⌫        ┃
        \\┢━━━━━┷━━┱──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┺━━┳━━━━━━━┫
        \\┃        ┃     │     │     │     │     │     │     │     │     │     │     │     ┃       ┃
        \\┃ ↹      ┃     │     │     │     │     │     │     │     │     │     │     │     ┃       ┃
        \\┣━━━━━━━━┻┱────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┺┓  ⏎   ┃
        \\┃         ┃     │     │     │     │     │     │     │     │     │     │     │     ┃      ┃
        \\┃ ⇬       ┃     │     │     │     │     │     │     │     │     │     │     │     ┃      ┃
        \\┣━━━━━━┳━━┹──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┲━━┷━━━━━┻━━━━━━┫
        \\┃      ┃     │     │     │     │     │     │     │     │     │     │     ┃               ┃
        \\┃ ⇧    ┃     │     │     │     │     │     │     │     │     │     │     ┃ ⇧             ┃
        \\┣━━━━━━┻┳━━━━┷━━┳━━┷━━━━┱┴─────┴─────┴─────┴─────┴─────┴─┲━━━┷━━━┳━┷━━━━━╋━━━━━━━┳━━━━━━━┫
        \\┃       ┃       ┃       ┃                                ┃       ┃       ┃       ┃       ┃
        \\┃ Ctrl  ┃ super ┃ Alt   ┃ ␣                              ┃ AltGr ┃ super ┃ menu  ┃ Ctrl  ┃
        \\┗━━━━━━━┻━━━━━━━┻━━━━━━━┹────────────────────────────────┺━━━━━━━┻━━━━━━━┻━━━━━━━┻━━━━━━━┛
        \\
    ;

    var diag = Diagnostic{ .allocator = std.testing.allocator };
    defer diag.deinit();

    const result = parseLayout(std.testing.allocator, Geometry.ISO, layout, .{ .diagnostic = &diag });

    try std.testing.expectEqual(ParsingError.CharAtBadPlace, result);
    try std.testing.expectEqual(2, diag.line);
    try std.testing.expectEqual(3, diag.column);
    try expectEqualOptionalString("second half of a dead key", diag.expected);
    try expectEqualOptionalString("a space", diag.found);
}
