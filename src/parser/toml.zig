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

    var keyboard_layout = try initKeyboardLayoutWithMetadata(allocator, parsed_toml, options);
    errdefer keyboard_layout.deinit();

    // TODO: line of the TOML is better for the feedback in diagnostic
    if (parsed_toml.full) |full_to_parse| {
        if (options.diagnostic) |diag| diag.arg = "full";

        try parseFullLayout(allocator, &keyboard_layout, full_to_parse, options);

        if (options.diagnostic) |diag| diag.arg = "";
    } else if (parsed_toml.base) |base_to_parse| {
        if (options.diagnostic) |diag| diag.arg = "base";

        try parseBaseLayout(allocator, &keyboard_layout, base_to_parse, options);

        if (parsed_toml.altgr) |altgr_to_parse| {
            if (options.diagnostic) |diag| diag.arg = "altgr";
            try parseAltgrLayout(allocator, &keyboard_layout, altgr_to_parse, options);
        }

        if (options.diagnostic) |diag| diag.arg = "";
    } else {
        return ParsingError.MissingLayout;
    }

    const arena = keyboard_layout.arena_allocator.allocator();

    // Spacebar
    // TODO: test with Ergo‑L if unicode char is decoded
    // const str = "He\u{301}"; // Hé
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

fn initKeyboardLayoutWithMetadata(
    allocator: std.mem.Allocator,
    parsed_toml: TomlContent,
    options: ParseOptions,
) !KeyboardLayout {
    var arena_allocator = std.heap.ArenaAllocator.init(allocator);
    errdefer arena_allocator.deinit();

    // The block is to scope this arena and avoid to use it after arena_allocator is copied
    // into keyboard layout and create a memory leak and weird memory overwrite
    const arena = arena_allocator.allocator();

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

    const layers = std.AutoHashMapUnmanaged(
        Layer,
        std.AutoHashMapUnmanaged(KeyCode, []const u8),
    ).empty;

    return KeyboardLayout{
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
}

/// Base + 1dk layers
fn parseBaseLayout(
    allocator: std.mem.Allocator,
    keyboard_layout: *KeyboardLayout,
    layout_to_parse: []const u8,
    options: ParseOptions,
) !void {
    const layers = .{ .base, .odk };
    return parseLayout(allocator, keyboard_layout, layout_to_parse, layers, options);
}

/// Base + AltGr layers
fn parseFullLayout(
    allocator: std.mem.Allocator,
    keyboard_layout: *KeyboardLayout,
    layout_to_parse: []const u8,
    options: ParseOptions,
) !void {
    const layers = .{ .base, .altgr };
    return parseLayout(allocator, keyboard_layout, layout_to_parse, layers, options);
}

/// AltGr layer only
fn parseAltgrLayout(
    allocator: std.mem.Allocator,
    keyboard_layout: *KeyboardLayout,
    layout_to_parse: []const u8,
    options: ParseOptions,
) !void {
    const layers = .{ .altgr, null };
    return parseLayout(allocator, keyboard_layout, layout_to_parse, layers, options);
}

/// Parse a layout according to the keyboard layout geometry with requested layers and put them in
/// keyboard layout
fn parseLayout(
    allocator: std.mem.Allocator,
    keyboard_layout: *KeyboardLayout,
    layout_to_parse: []const u8,
    layers: struct { Layer, ?Layer },
    options: ParseOptions,
) !void {
    const arena = keyboard_layout.arena_allocator.allocator();

    const graph = try Graphemes.init(allocator);
    defer graph.deinit(allocator);

    const case = try LetterCasing.init(allocator);
    defer case.deinit(allocator);

    var base_layer: ?std.AutoHashMapUnmanaged(KeyCode, []const u8) = null;
    var base_layer_shift: ?std.AutoHashMapUnmanaged(KeyCode, []const u8) = null;

    var altgr_odk_layer: ?std.AutoHashMapUnmanaged(KeyCode, []const u8) = null;
    var altgr_odk_layer_shift: ?std.AutoHashMapUnmanaged(KeyCode, []const u8) = null;
    var altgr_odk_layer_type: ?Layer = null;

    if (layers[0] == .base) {
        // Base layers are always in keyboard layout
        base_layer = .empty;
        base_layer_shift = .empty;
    }

    if (layers[0] == .altgr or layers[1] == .altgr) {
        altgr_odk_layer = .empty;
        altgr_odk_layer_shift = .empty;
        altgr_odk_layer_type = .altgr;
    } else if (layers[0] == .odk or layers[1] == .odk) {
        altgr_odk_layer = .empty;
        altgr_odk_layer_shift = .empty;
        altgr_odk_layer_type = .odk;
    }

    const rows = keyboard_layout.geometry.getKeys();
    const template = keyboard_layout.geometry.getTemplate();

    var rows_idx: usize = 0;
    var rows_keys_idx: usize = 0;
    var in_line_row: usize = 0;
    var in_line_column: usize = 0;
    var in_key_column: usize = 0;
    var layout_to_parse_line: usize = 1;
    var layout_to_parse_column: usize = 1;
    var dead_key_in_parsing = false;

    var template_iter = graph.iterator(template);
    var layout_to_parse_iter = graph.iterator(layout_to_parse);

    // Skip the first empty line
    if (layout_to_parse_iter.next()) |ltpc| {
        if (!std.mem.eql(u8, "\n", ltpc.bytes(layout_to_parse))) {
            return options.setParsingError(
                ParsingError.WrongStructure,
                layout_to_parse_line,
                layout_to_parse_column,
                "\n",
                ltpc.bytes(layout_to_parse),
            );
        }
    }

    while (template_iter.next()) |tc| {
        if (layout_to_parse_iter.next()) |ltpc| {
            const template_char = tc.bytes(template);
            const layout_char = ltpc.bytes(layout_to_parse);

            if (rows_idx >= rows.len or // Template last lines
                in_line_row == 0 or // Template first line
                in_line_column < rows[rows_idx].offset or // Row offset
                rows_keys_idx >= rows[rows_idx].keys.len or // End of line
                (in_key_column == 4 or in_key_column == 5) // Key separation
            ) {
                // Template and layout to parse should have same structure
                if (!std.mem.eql(u8, template_char, layout_char)) {
                    return options.setParsingError(
                        ParsingError.WrongStructure,
                        layout_to_parse_line,
                        layout_to_parse_column,
                        template_char,
                        layout_char,
                    );
                }
            } else {
                const is_char_in_layout = !std.mem.eql(u8, layout_char, " ");

                if (in_key_column == 0 or in_key_column == 2) {
                    if (is_char_in_layout) {
                        if (std.mem.eql(u8, layout_char, "*")) {
                            dead_key_in_parsing = true;
                        } else {
                            // No other char than dead key in these columns
                            return options.setParsingError(
                                ParsingError.CharAtBadPlace,
                                layout_to_parse_line,
                                layout_to_parse_column,
                                "nothing or *",
                                layout_char,
                            );
                        }
                    }
                } else if (in_key_column == 1 or in_key_column == 3) {
                    if (is_char_in_layout) {
                        var layer_no_shift: *std.AutoHashMapUnmanaged(KeyCode, []const u8) = undefined;
                        var layer_shift: *std.AutoHashMapUnmanaged(KeyCode, []const u8) = undefined;

                        if (in_key_column == 1) {
                            // Append base key if any
                            if (base_layer == null) {
                                // Has char in first column but no base layer
                                return options.setParsingError(
                                    ParsingError.CharAtBadPlace,
                                    layout_to_parse_line,
                                    layout_to_parse_column,
                                    " ",
                                    layout_char,
                                );
                            }

                            layer_no_shift = &base_layer.?;
                            layer_shift = &base_layer_shift.?;
                        } else if (in_key_column == 3) {
                            // Append altgr or 1dk key if any
                            if (altgr_odk_layer == null) {
                                // Has char in third column but no altgr/1dk layer
                                return options.setParsingError(
                                    ParsingError.CharAtBadPlace,
                                    layout_to_parse_line,
                                    layout_to_parse_column,
                                    " ",
                                    layout_char,
                                );
                            }

                            layer_no_shift = &altgr_odk_layer.?;
                            layer_shift = &altgr_odk_layer_shift.?;
                        }

                        var key_to_add = std.ArrayList(u8).empty;

                        if (dead_key_in_parsing) {
                            // Dead key '*' to keep before layout char
                            dead_key_in_parsing = false;
                            try key_to_add.append(arena, '*');
                            // TODO: do we check here that it is a valid dead key? kalamine/layout.py:311
                        }

                        try key_to_add.appendSlice(arena, layout_char);
                        const key_value = try key_to_add.toOwnedSlice(arena);

                        const key = rows[rows_idx].keys[rows_keys_idx];

                        if (in_line_row == 1) {
                            // Shifted char
                            try layer_shift.put(arena, key, key_value);
                        } else {
                            // Non-shifted char
                            try layer_no_shift.put(arena, key, key_value);
                        }
                    } else if (dead_key_in_parsing) {
                        // Missing second half of dead key
                        return options.setParsingError(
                            ParsingError.CharAtBadPlace,
                            layout_to_parse_line,
                            layout_to_parse_column,
                            "second half of a dead key",
                            layout_char,
                        );
                    }
                }
            }

            // Set the counters
            if (std.mem.eql(u8, template_char, "\n")) {
                if (in_line_row >= nb_lines_per_key - 1) {
                    in_line_row = 0;
                    rows_idx += 1;
                } else {
                    in_line_row += 1;
                }

                rows_keys_idx = 0;
                in_line_column = 0;
                in_key_column = 0;
                layout_to_parse_line += 1;
                layout_to_parse_column = 1;
            } else {
                if (in_key_column >= nb_columns_per_key - 1) {
                    in_key_column = 0;
                    rows_keys_idx += 1;
                } else if (rows_idx < rows.len and
                    in_line_column >= rows[rows_idx].offset)
                {
                    // Skip offset, not a key
                    in_key_column += 1;
                }

                in_line_column += 1;
                layout_to_parse_column += 1;
            }
        } else {
            // Template has characters but not the layout to parse
            return options.setParsingError(
                ParsingError.WrongStructure,
                layout_to_parse_line,
                layout_to_parse_column,
                tc.bytes(template),
                "nothing",
            );
        }
    }

    // Skip the last empty line
    if (layout_to_parse_iter.next()) |ltpc| {
        if (!std.mem.eql(u8, "\n", ltpc.bytes(layout_to_parse))) {
            return options.setParsingError(
                ParsingError.WrongStructure,
                layout_to_parse_line,
                layout_to_parse_column,
                "\n",
                ltpc.bytes(layout_to_parse),
            );
        }
        layout_to_parse_line += 1;
        layout_to_parse_column = 1;
    } else {
        return options.setParsingError(
            ParsingError.WrongStructure,
            layout_to_parse_line,
            layout_to_parse_column,
            "\n",
            "nothing",
        );
    }

    if (layout_to_parse_iter.next()) |ltpc| {
        // Layout to parse has characters but not the template
        return options.setParsingError(
            ParsingError.WrongStructure,
            layout_to_parse_line,
            layout_to_parse_column,
            "nothing",
            ltpc.bytes(layout_to_parse),
        );
    }

    // Add non-shifted value to base layer
    if (base_layer_shift) |layer_shift| {
        var it = layer_shift.iterator();
        while (it.next()) |entry| {
            const key_code = entry.key_ptr;
            const key_value = entry.value_ptr;
            if (!base_layer.?.contains(key_code.*)) {
                const key_to_put_base = try case.toLowerStr(arena, key_value.*);
                try base_layer.?.put(arena, key_code.*, key_to_put_base);
            }
        }
    }

    // Add shifted value to altgr/1dk layer
    if (altgr_odk_layer) |layer_no_shift| {
        var it = layer_no_shift.iterator();
        while (it.next()) |entry| {
            const key_code = entry.key_ptr;
            const key_value = entry.value_ptr;
            if (!altgr_odk_layer_shift.?.contains(key_code.*)) {
                const key_to_put_shift = try case.toUpperStr(arena, key_value.*);
                try altgr_odk_layer_shift.?.put(arena, key_code.*, key_to_put_shift);
            }
        }
    }

    // Add base layer to keyboard layout if any
    if (base_layer != null) {
        try keyboard_layout.layers.put(arena, .base, base_layer.?);
        try keyboard_layout.layers.put(arena, .shift, base_layer_shift.?);
    }

    // Add altgr/1dk layer to keyboard layout if any
    if (altgr_odk_layer_type == .altgr and
        (altgr_odk_layer.?.size != 0 or altgr_odk_layer_shift.?.size != 0))
    {
        try keyboard_layout.layers.put(arena, .altgr, altgr_odk_layer.?);
        try keyboard_layout.layers.put(arena, .altgr_shift, altgr_odk_layer_shift.?);
    } else if (altgr_odk_layer_type == .odk and
        (altgr_odk_layer.?.size != 0 or altgr_odk_layer_shift.?.size != 0))
    {
        try keyboard_layout.layers.put(arena, .odk, altgr_odk_layer.?);
        try keyboard_layout.layers.put(arena, .odk_shift, altgr_odk_layer_shift.?);
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
        \\url         = "https://github.com/OneDeadKey/kalamine"
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
    try expectEqualOptionalString("https://github.com/OneDeadKey/kalamine", result.url);
    try expectEqualOptionalString("0.0.1", result.version);
    try std.testing.expectEqual(Geometry.ANSI, result.geometry);

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
        \\url         = "https://github.com/OneDeadKey/kalamine"
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
    try expectEqualOptionalString("https://github.com/OneDeadKey/kalamine", result.url);
    try expectEqualOptionalString("0.0.1", result.version);
    try std.testing.expectEqual(Geometry.ANSI, result.geometry);

    try std.testing.expectEqual(4, result.layers.size);

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
        \\url         = "https://github.com/OneDeadKey/kalamine"
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
    try expectEqualOptionalString("https://github.com/OneDeadKey/kalamine", result.url);
    try expectEqualOptionalString("0.0.1", result.version);
    try std.testing.expectEqual(Geometry.ANSI, result.geometry);

    try std.testing.expectEqual(4, result.layers.size);

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
        \\url         = "https://github.com/OneDeadKey/kalamine"
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
    try expectEqualOptionalString("https://github.com/OneDeadKey/kalamine", result.url);
    try expectEqualOptionalString("0.0.1", result.version);
    try std.testing.expectEqual(Geometry.ANSI, result.geometry);

    try std.testing.expectEqual(4, result.layers.size);

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
        \\url         = "https://github.com/OneDeadKey/kalamine"
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
    try expectEqualOptionalString("https://github.com/OneDeadKey/kalamine", result.url);
    try expectEqualOptionalString("0.0.1", result.version);
    try std.testing.expectEqual(Geometry.ANSI, result.geometry);

    try std.testing.expectEqual(2, result.layers.size);

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
}

test "parseKeyboardLayoutFromToml with empty base" {
    const toml_to_parse =
        \\name = "test"
        \\geometry = "ISO"
        \\base = '''
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
        \\'''
        \\
    ;
    var reader = std.Io.Reader.fixed(toml_to_parse);

    var result = try parseKeyboardLayoutFromToml(std.testing.allocator, &reader, .{});
    defer result.deinit();

    try std.testing.expectEqualStrings("test", result.name);
    try std.testing.expectEqualStrings("test", result.name8);
    try expectEqualOptionalString(null, result.locale);
    try expectEqualOptionalString(null, result.variant);
    try expectEqualOptionalString(null, result.author);
    try expectEqualOptionalString(null, result.description);
    try expectEqualOptionalString(null, result.url);
    try expectEqualOptionalString(null, result.version);
    try std.testing.expectEqual(Geometry.ISO, result.geometry);

    try std.testing.expectEqual(2, result.layers.size);

    const expected_base_layer = [_]struct { KeyCode, []const u8 }{
        .{ .spce, " " },
    };

    try testAssertLayer(result.layers.get(.base).?, &expected_base_layer);

    const expected_shift_layer = [_]struct { KeyCode, []const u8 }{
        .{ .spce, " " },
    };

    try testAssertLayer(result.layers.get(.shift).?, &expected_shift_layer);
}

test "parseKeyboardLayoutFromToml no first line return" {
    const toml_to_parse =
        \\name = "test"
        \\geometry = "ISO"
        \\base = '''┌─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┲━━━━━━━━━━┓
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
        \\'''
        \\
    ;
    var reader = std.Io.Reader.fixed(toml_to_parse);
    var diag = Diagnostic{ .allocator = std.testing.allocator };
    defer diag.deinit();

    const result = parseKeyboardLayoutFromToml(std.testing.allocator, &reader, .{ .diagnostic = &diag });

    try std.testing.expectEqual(ParsingError.WrongStructure, result);
    try std.testing.expectEqualStrings("base", diag.arg);
    try std.testing.expectEqual(1, diag.line);
    try std.testing.expectEqual(1, diag.column);
    try expectEqualOptionalString("a line return", diag.expected);
    try expectEqualOptionalString("┌", diag.found);
}

test "parseKeyboardLayoutFromToml no last line return" {
    const toml_to_parse =
        \\name = "test"
        \\geometry = "ISO"
        \\base = '''
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
        \\┗━━━━━━━┻━━━━━━━┻━━━━━━━┹────────────────────────────────┺━━━━━━━┻━━━━━━━┻━━━━━━━┻━━━━━━━┛'''
        \\
    ;
    var reader = std.Io.Reader.fixed(toml_to_parse);
    var diag = Diagnostic{ .allocator = std.testing.allocator };
    defer diag.deinit();

    const result = parseKeyboardLayoutFromToml(std.testing.allocator, &reader, .{ .diagnostic = &diag });

    try std.testing.expectEqual(ParsingError.WrongStructure, result);
    try std.testing.expectEqualStrings("base", diag.arg);
    try std.testing.expectEqual(16, diag.line);
    try std.testing.expectEqual(91, diag.column);
    try expectEqualOptionalString("a line return", diag.expected);
    try expectEqualOptionalString("nothing", diag.found);
}

test "parseKeyboardLayoutFromToml truncated layout" {
    const toml_to_parse =
        \\name = "test"
        \\geometry = "ISO"
        \\base = '''
        \\┌─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┲━━━━━━━━━━┓
        \\'''
        \\
    ;
    var reader = std.Io.Reader.fixed(toml_to_parse);
    var diag = Diagnostic{ .allocator = std.testing.allocator };
    defer diag.deinit();

    const result = parseKeyboardLayoutFromToml(std.testing.allocator, &reader, .{ .diagnostic = &diag });

    try std.testing.expectEqual(ParsingError.WrongStructure, result);
    try std.testing.expectEqualStrings("base", diag.arg);
    try std.testing.expectEqual(2, diag.line);
    try std.testing.expectEqual(1, diag.column);
    try expectEqualOptionalString("│", diag.expected);
    try expectEqualOptionalString("nothing", diag.found);
}

test "parseKeyboardLayoutFromToml truncated layout line return" {
    const toml_to_parse =
        \\name = "test"
        \\geometry = "ISO"
        \\base = '''
        \\┌─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┲━━━━━━━━━━┓'''
        \\
    ;
    var reader = std.Io.Reader.fixed(toml_to_parse);
    var diag = Diagnostic{ .allocator = std.testing.allocator };
    defer diag.deinit();

    const result = parseKeyboardLayoutFromToml(std.testing.allocator, &reader, .{ .diagnostic = &diag });

    try std.testing.expectEqual(ParsingError.WrongStructure, result);
    try std.testing.expectEqualStrings("base", diag.arg);
    try std.testing.expectEqual(1, diag.line);
    try std.testing.expectEqual(91, diag.column);
    try expectEqualOptionalString("a line return", diag.expected);
    try expectEqualOptionalString("nothing", diag.found);
}

test "parseKeyboardLayoutFromToml too many char" {
    const toml_to_parse =
        \\name = "test"
        \\geometry = "ISO"
        \\base = '''
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
        \\a'''
        \\
    ;
    var reader = std.Io.Reader.fixed(toml_to_parse);
    var diag = Diagnostic{ .allocator = std.testing.allocator };
    defer diag.deinit();

    const result = parseKeyboardLayoutFromToml(std.testing.allocator, &reader, .{ .diagnostic = &diag });

    try std.testing.expectEqual(ParsingError.WrongStructure, result);
    try std.testing.expectEqualStrings("base", diag.arg);
    try std.testing.expectEqual(17, diag.line);
    try std.testing.expectEqual(1, diag.column);
    try expectEqualOptionalString("nothing", diag.expected);
    try expectEqualOptionalString("a", diag.found);
}

test "parseKeyboardLayoutFromToml too many line returns" {
    const toml_to_parse =
        \\name = "test"
        \\geometry = "ISO"
        \\base = '''
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
        \\'''
        \\
    ;
    var reader = std.Io.Reader.fixed(toml_to_parse);
    var diag = Diagnostic{ .allocator = std.testing.allocator };
    defer diag.deinit();

    const result = parseKeyboardLayoutFromToml(std.testing.allocator, &reader, .{ .diagnostic = &diag });

    try std.testing.expectEqual(ParsingError.WrongStructure, result);
    try std.testing.expectEqualStrings("base", diag.arg);
    try std.testing.expectEqual(17, diag.line);
    try std.testing.expectEqual(1, diag.column);
    try expectEqualOptionalString("nothing", diag.expected);
    try expectEqualOptionalString("a line return", diag.found);
}

test "parseKeyboardLayoutFromToml wrong indentation with spaces" {
    const toml_to_parse =
        \\name = "test"
        \\geometry = "ISO"
        \\base = '''
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
        \\'''
        \\
    ;
    var reader = std.Io.Reader.fixed(toml_to_parse);
    var diag = Diagnostic{ .allocator = std.testing.allocator };
    defer diag.deinit();

    const result = parseKeyboardLayoutFromToml(std.testing.allocator, &reader, .{ .diagnostic = &diag });

    try std.testing.expectEqual(ParsingError.WrongStructure, result);
    try std.testing.expectEqualStrings("base", diag.arg);
    try std.testing.expectEqual(1, diag.line);
    try std.testing.expectEqual(1, diag.column);
    try expectEqualOptionalString("┌", diag.expected);
    try expectEqualOptionalString("a space", diag.found);
}

test "parseKeyboardLayoutFromToml wrong indentation with tab" {
    // Cannot put tab in multiline string
    const toml_to_parse = "name = \"test\"\ngeometry = \"ISO\"\nbase = '''\n\t┌─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┲━━━━━━━━━━┓\n'''\n";

    var reader = std.Io.Reader.fixed(toml_to_parse);
    var diag = Diagnostic{ .allocator = std.testing.allocator };
    defer diag.deinit();

    const result = parseKeyboardLayoutFromToml(std.testing.allocator, &reader, .{ .diagnostic = &diag });

    try std.testing.expectEqual(ParsingError.WrongStructure, result);
    try std.testing.expectEqualStrings("base", diag.arg);
    try std.testing.expectEqual(1, diag.line);
    try std.testing.expectEqual(1, diag.column);
    try expectEqualOptionalString("┌", diag.expected);
    try expectEqualOptionalString("a tabulation", diag.found);
}

test "parseKeyboardLayoutFromToml should not have char in offset" {
    const toml_to_parse =
        \\name = "test"
        \\geometry = "ISO"
        \\base = '''
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
        \\'''
        \\
    ;
    var reader = std.Io.Reader.fixed(toml_to_parse);
    var diag = Diagnostic{ .allocator = std.testing.allocator };
    defer diag.deinit();

    const result = parseKeyboardLayoutFromToml(std.testing.allocator, &reader, .{ .diagnostic = &diag });

    try std.testing.expectEqual(ParsingError.WrongStructure, result);
    try std.testing.expectEqualStrings("base", diag.arg);
    try std.testing.expectEqual(6, diag.line);
    try std.testing.expectEqual(7, diag.column);
    try expectEqualOptionalString("a space", diag.expected);
    try expectEqualOptionalString("a", diag.found);
}

test "parseKeyboardLayoutFromToml should not have char after keys" {
    const toml_to_parse =
        \\name = "test"
        \\geometry = "ISO"
        \\base = '''
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
        \\'''
        \\
    ;
    var reader = std.Io.Reader.fixed(toml_to_parse);
    var diag = Diagnostic{ .allocator = std.testing.allocator };
    defer diag.deinit();

    const result = parseKeyboardLayoutFromToml(std.testing.allocator, &reader, .{ .diagnostic = &diag });

    try std.testing.expectEqual(ParsingError.WrongStructure, result);
    try std.testing.expectEqualStrings("base", diag.arg);
    try std.testing.expectEqual(6, diag.line);
    try std.testing.expectEqual(86, diag.column);
    try expectEqualOptionalString("a space", diag.expected);
    try expectEqualOptionalString("a", diag.found);
}

test "parseKeyboardLayoutFromToml should not have char in last line" {
    const toml_to_parse =
        \\name = "test"
        \\geometry = "ISO"
        \\base = '''
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
        \\'''
        \\
    ;
    var reader = std.Io.Reader.fixed(toml_to_parse);
    var diag = Diagnostic{ .allocator = std.testing.allocator };
    defer diag.deinit();

    const result = parseKeyboardLayoutFromToml(std.testing.allocator, &reader, .{ .diagnostic = &diag });

    try std.testing.expectEqual(ParsingError.WrongStructure, result);
    try std.testing.expectEqualStrings("base", diag.arg);
    try std.testing.expectEqual(15, diag.line);
    try std.testing.expectEqual(41, diag.column);
    try expectEqualOptionalString("a space", diag.expected);
    try expectEqualOptionalString("a", diag.found);
}

test "parseKeyboardLayoutFromToml should not have char in last column of a key" {
    const toml_to_parse =
        \\name = "test"
        \\geometry = "ISO"
        \\base = '''
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
        \\'''
        \\
    ;
    var reader = std.Io.Reader.fixed(toml_to_parse);
    var diag = Diagnostic{ .allocator = std.testing.allocator };
    defer diag.deinit();

    const result = parseKeyboardLayoutFromToml(std.testing.allocator, &reader, .{ .diagnostic = &diag });

    try std.testing.expectEqual(ParsingError.WrongStructure, result);
    try std.testing.expectEqualStrings("base", diag.arg);
    try std.testing.expectEqual(3, diag.line);
    try std.testing.expectEqual(42, diag.column);
    try expectEqualOptionalString("a space", diag.expected);
    try expectEqualOptionalString("a", diag.found);
}

test "parseKeyboardLayoutFromToml should not have char in 1st column of a key" {
    const toml_to_parse =
        \\name = "test"
        \\geometry = "ISO"
        \\base = '''
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
        \\'''
        \\
    ;
    var reader = std.Io.Reader.fixed(toml_to_parse);
    var diag = Diagnostic{ .allocator = std.testing.allocator };
    defer diag.deinit();

    const result = parseKeyboardLayoutFromToml(std.testing.allocator, &reader, .{ .diagnostic = &diag });

    try std.testing.expectEqual(ParsingError.CharAtBadPlace, result);
    try std.testing.expectEqualStrings("base", diag.arg);
    try std.testing.expectEqual(5, diag.line);
    try std.testing.expectEqual(41, diag.column);
    try expectEqualOptionalString("nothing or *", diag.expected);
    try expectEqualOptionalString("a", diag.found);
}

test "parseKeyboardLayoutFromToml should not have char in 3rd column of a key" {
    const toml_to_parse =
        \\name = "test"
        \\geometry = "ISO"
        \\full = '''
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
        \\'''
        \\
    ;
    var reader = std.Io.Reader.fixed(toml_to_parse);
    var diag = Diagnostic{ .allocator = std.testing.allocator };
    defer diag.deinit();

    const result = parseKeyboardLayoutFromToml(std.testing.allocator, &reader, .{ .diagnostic = &diag });

    try std.testing.expectEqual(ParsingError.CharAtBadPlace, result);
    try std.testing.expectEqualStrings("full", diag.arg);
    try std.testing.expectEqual(5, diag.line);
    try std.testing.expectEqual(43, diag.column);
    try expectEqualOptionalString("nothing or *", diag.expected);
    try expectEqualOptionalString("a", diag.found);
}

test "parseKeyboardLayoutFromToml empty dead key" {
    const toml_to_parse =
        \\name = "test"
        \\geometry = "ISO"
        \\base = '''
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
        \\'''
        \\
    ;
    var reader = std.Io.Reader.fixed(toml_to_parse);
    var diag = Diagnostic{ .allocator = std.testing.allocator };
    defer diag.deinit();

    const result = parseKeyboardLayoutFromToml(std.testing.allocator, &reader, .{ .diagnostic = &diag });

    try std.testing.expectEqual(ParsingError.CharAtBadPlace, result);
    try std.testing.expectEqualStrings("base", diag.arg);
    try std.testing.expectEqual(2, diag.line);
    try std.testing.expectEqual(3, diag.column);
    try expectEqualOptionalString("second half of a dead key", diag.expected);
    try expectEqualOptionalString("a space", diag.found);
}

test "parseKeyboardLayoutFromToml altgr without a base" {
    const toml_to_parse =
        \\name = "test"
        \\geometry = "ISO"
        \\altgr = '''
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
        \\'''
        \\
    ;
    var reader = std.Io.Reader.fixed(toml_to_parse);
    var diag = Diagnostic{ .allocator = std.testing.allocator };
    defer diag.deinit();

    const result = parseKeyboardLayoutFromToml(std.testing.allocator, &reader, .{ .diagnostic = &diag });

    try std.testing.expectEqual(ParsingError.MissingLayout, result);
    try std.testing.expectEqualStrings("", diag.arg);
    try std.testing.expectEqual(0, diag.line);
    try std.testing.expectEqual(0, diag.column);
    try expectEqualOptionalString(null, diag.expected);
    try expectEqualOptionalString(null, diag.found);
}

test "parseKeyboardLayoutFromToml error in altgr" {
    const toml_to_parse =
        \\name = "test"
        \\geometry = "ISO"
        \\base = '''
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
        \\'''
        \\
        \\altgr = '''
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
        \\'''
        \\
    ;
    var reader = std.Io.Reader.fixed(toml_to_parse);
    var diag = Diagnostic{ .allocator = std.testing.allocator };
    defer diag.deinit();

    const result = parseKeyboardLayoutFromToml(std.testing.allocator, &reader, .{ .diagnostic = &diag });

    try std.testing.expectEqual(ParsingError.WrongStructure, result);
    try std.testing.expectEqualStrings("altgr", diag.arg);
    try std.testing.expectEqual(15, diag.line);
    try std.testing.expectEqual(41, diag.column);
    try expectEqualOptionalString("a space", diag.expected);
    try expectEqualOptionalString("a", diag.found);
}
