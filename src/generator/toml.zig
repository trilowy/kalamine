//! Output a keyboard layout to TOML representation

const std = @import("std");
const Graphemes = @import("Graphemes");
const Grapheme = Graphemes.Grapheme;
const LetterCasing = @import("LetterCasing");
const layout = @import("../layout.zig");
const KeyboardLayout = layout.KeyboardLayout;
const Layer = layout.Layer;
const KeyCode = layout.KeyCode;
const layout_parser = @import("../parser/toml.zig");
const nb_lines_per_key = layout_parser.nb_lines_per_key;
const nb_columns_per_key = layout_parser.nb_columns_per_key;

/// Base + 1dk layers
pub fn getBase(
    allocator: std.mem.Allocator,
    keyboard_layout: *const KeyboardLayout,
) ![]u8 {
    const layers = .{ .base, .odk };
    return fillTemplate(allocator, keyboard_layout, layers);
}

/// Base + AltGr layers
pub fn getFull(
    allocator: std.mem.Allocator,
    keyboard_layout: *const KeyboardLayout,
) ![]u8 {
    const layers = .{ .base, .altgr };
    return fillTemplate(allocator, keyboard_layout, layers);
}

/// AltGr layer only
pub fn getAltgr(
    allocator: std.mem.Allocator,
    keyboard_layout: *const KeyboardLayout,
) ![]u8 {
    const layers = .{ .altgr, null };
    return fillTemplate(allocator, keyboard_layout, layers);
}

/// Fill a template with requested layers
fn fillTemplate(
    allocator: std.mem.Allocator,
    keyboard_layout: *const KeyboardLayout,
    layers: struct { Layer, ?Layer },
) ![]u8 {
    const graph = try Graphemes.init(allocator);
    defer graph.deinit(allocator);

    const case = try LetterCasing.init(allocator);
    defer case.deinit(allocator);

    var base_layer: ?std.AutoHashMapUnmanaged(KeyCode, []const u8) = null;
    var base_layer_shift: ?std.AutoHashMapUnmanaged(KeyCode, []const u8) = null;

    var altgr_odk_layer: ?std.AutoHashMapUnmanaged(KeyCode, []const u8) = null;
    var altgr_odk_layer_shift: ?std.AutoHashMapUnmanaged(KeyCode, []const u8) = null;

    if (layers[0] == .base) {
        base_layer = keyboard_layout.layers.get(layers[0]);
        base_layer_shift = keyboard_layout.layers.get(layers[0].shifted());
    } else if ((layers[0] == .altgr and keyboard_layout.has_altgr) or
        (layers[0] == .odk and keyboard_layout.has_1dk))
    {
        altgr_odk_layer = keyboard_layout.layers.get(layers[0]);
        altgr_odk_layer_shift = keyboard_layout.layers.get(layers[0].shifted());
    }

    if ((layers[1] == .altgr and keyboard_layout.has_altgr) or
        (layers[1] == .odk and keyboard_layout.has_1dk))
    {
        altgr_odk_layer = keyboard_layout.layers.get(layers[1].?);
        altgr_odk_layer_shift = keyboard_layout.layers.get(layers[1].?.shifted());
    }

    const rows = keyboard_layout.geometry.getKeys();
    const template = keyboard_layout.geometry.getTemplate();

    var template_to_fill = std.ArrayList(u8).empty;
    errdefer template_to_fill.deinit(allocator);

    var rows_idx: usize = 0;
    var rows_keys_idx: usize = 0;
    var in_line_row: usize = 0;
    var in_line_column: usize = 0;
    var in_key_column: usize = 0;
    var template_iter = graph.iterator(template);

    while (template_iter.next()) |tc| {
        const template_char = tc.bytes(template);

        // At the end, append all the rest of the template
        if (rows_idx >= rows.len) {
            try template_to_fill.appendSlice(allocator, template_char);
            continue;
        }

        if (in_line_row == 0 or // Template first line
            in_line_column < rows[rows_idx].offset or // Row offset
            rows_keys_idx >= rows[rows_idx].keys.len or // End of line
            (in_key_column == 4 or in_key_column == 5) // Key separation
        ) {
            try template_to_fill.appendSlice(allocator, template_char);
        } else {
            const key = rows[rows_idx].keys[rows_keys_idx];
            var key_value: ?[]const u8 = null;

            if (in_key_column == 0) {
                // Append base key if any
                if (in_line_row == 1) {
                    key_value = if (base_layer_shift) |layer_value|
                        layer_value.get(key)
                    else
                        null;
                } else {
                    key_value = if (base_layer) |layer_value|
                        layer_value.get(key)
                    else
                        null;

                    if (key_value) |kv| {
                        // Check shifted key is not the same
                        if (base_layer_shift) |layer_value| {
                            if (layer_value.get(key)) |shift_key_value| {
                                const lower_shifted_key = try case.toLowerStr(allocator, shift_key_value);
                                defer allocator.free(lower_shifted_key);

                                if (std.mem.eql(u8, lower_shifted_key, kv)) {
                                    key_value = null;
                                }
                            }
                        }
                    }
                }
            } else if (in_key_column == 2) {
                // Append AltGr or 1dk key if any
                if (in_line_row == 1) {
                    key_value = if (altgr_odk_layer_shift) |layer_value|
                        layer_value.get(key)
                    else
                        null;

                    if (key_value) |shift_key_value| {
                        // Check not shifted key is not the same
                        if (altgr_odk_layer) |layer_value| {
                            if (layer_value.get(key)) |kv| {
                                const lower_shifted_key = try case.toLowerStr(allocator, shift_key_value);
                                defer allocator.free(lower_shifted_key);

                                if (std.mem.eql(u8, lower_shifted_key, kv)) {
                                    key_value = null;
                                }
                            }
                        }
                    }
                } else {
                    key_value = if (altgr_odk_layer) |layer_value|
                        layer_value.get(key)
                    else
                        null;
                }
            }

            if (key_value) |key_char| {
                var key_char_iter = graph.iterator(key_char);
                var key_char_len: usize = 0;
                while (key_char_iter.next()) |_| {
                    key_char_len += 1;
                }

                if (key_char_len == 1) {
                    try template_to_fill.append(allocator, ' ');
                }

                try template_to_fill.appendSlice(allocator, key_char);
            } else if (in_key_column == 0 or in_key_column == 2) {
                // No key we fill with empty
                try template_to_fill.appendSlice(allocator, "  ");
            }
        }

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
        } else {
            if (in_key_column >= nb_columns_per_key - 1) {
                in_key_column = 0;
                rows_keys_idx += 1;
            } else if (in_line_column >= rows[rows_idx].offset) {
                // Skip offset, not a key
                in_key_column += 1;
            }

            in_line_column += 1;
        }
    }

    return template_to_fill.toOwnedSlice(allocator);
}

fn testInitKeyboardLayout(arena: *std.heap.ArenaAllocator) !KeyboardLayout {
    const allocator = arena.allocator();

    var base_layer = std.AutoHashMapUnmanaged(KeyCode, []const u8).empty;

    try base_layer.put(allocator, .tlde, "`");
    try base_layer.put(allocator, .ae01, "1");
    try base_layer.put(allocator, .ae02, "2");
    try base_layer.put(allocator, .ae03, "3");
    try base_layer.put(allocator, .ae04, "4");
    try base_layer.put(allocator, .ae05, "5");
    try base_layer.put(allocator, .ae06, "6");
    try base_layer.put(allocator, .ae07, "7");
    try base_layer.put(allocator, .ae08, "8");
    try base_layer.put(allocator, .ae09, "9");
    try base_layer.put(allocator, .ae10, "0");
    try base_layer.put(allocator, .ae11, "-");
    try base_layer.put(allocator, .ae12, "=");

    try base_layer.put(allocator, .ad01, "q");
    try base_layer.put(allocator, .ad02, "w");
    try base_layer.put(allocator, .ad03, "e");
    try base_layer.put(allocator, .ad04, "r");
    try base_layer.put(allocator, .ad05, "t");
    try base_layer.put(allocator, .ad06, "y");
    try base_layer.put(allocator, .ad07, "u");
    try base_layer.put(allocator, .ad08, "i");
    try base_layer.put(allocator, .ad09, "o");
    try base_layer.put(allocator, .ad10, "p");
    try base_layer.put(allocator, .ad11, "[");
    try base_layer.put(allocator, .ad12, "]");

    try base_layer.put(allocator, .ac01, "a");
    try base_layer.put(allocator, .ac02, "s");
    try base_layer.put(allocator, .ac03, "d");
    try base_layer.put(allocator, .ac04, "f");
    try base_layer.put(allocator, .ac05, "g");
    try base_layer.put(allocator, .ac06, "h");
    try base_layer.put(allocator, .ac07, "j");
    try base_layer.put(allocator, .ac08, "k");
    try base_layer.put(allocator, .ac09, "l");
    try base_layer.put(allocator, .ac10, ";");
    try base_layer.put(allocator, .ac11, "**");
    try base_layer.put(allocator, .bksl, "\\");

    try base_layer.put(allocator, .ab01, "z");
    try base_layer.put(allocator, .ab02, "x");
    try base_layer.put(allocator, .ab03, "c");
    try base_layer.put(allocator, .ab04, "v");
    try base_layer.put(allocator, .ab05, "b");
    try base_layer.put(allocator, .ab06, "n");
    try base_layer.put(allocator, .ab07, "m");
    try base_layer.put(allocator, .ab08, ",");
    try base_layer.put(allocator, .ab09, ".");
    try base_layer.put(allocator, .ab10, "/");

    try base_layer.put(allocator, .spce, " ");

    var shift_layer = std.AutoHashMapUnmanaged(KeyCode, []const u8).empty;

    try shift_layer.put(allocator, .tlde, "~");
    try shift_layer.put(allocator, .ae01, "!");
    try shift_layer.put(allocator, .ae02, "@");
    try shift_layer.put(allocator, .ae03, "#");
    try shift_layer.put(allocator, .ae04, "$");
    try shift_layer.put(allocator, .ae05, "%");
    try shift_layer.put(allocator, .ae06, "^");
    try shift_layer.put(allocator, .ae07, "&");
    try shift_layer.put(allocator, .ae08, "*");
    try shift_layer.put(allocator, .ae09, "(");
    try shift_layer.put(allocator, .ae10, ")");
    try shift_layer.put(allocator, .ae11, "_");
    try shift_layer.put(allocator, .ae12, "+");

    try shift_layer.put(allocator, .ad01, "Q");
    try shift_layer.put(allocator, .ad02, "W");
    try shift_layer.put(allocator, .ad03, "E");
    try shift_layer.put(allocator, .ad04, "R");
    try shift_layer.put(allocator, .ad05, "T");
    try shift_layer.put(allocator, .ad06, "Y");
    try shift_layer.put(allocator, .ad07, "U");
    try shift_layer.put(allocator, .ad08, "I");
    try shift_layer.put(allocator, .ad09, "O");
    try shift_layer.put(allocator, .ad10, "P");
    try shift_layer.put(allocator, .ad11, "{");
    try shift_layer.put(allocator, .ad12, "}");

    try shift_layer.put(allocator, .ac01, "A");
    try shift_layer.put(allocator, .ac02, "S");
    try shift_layer.put(allocator, .ac03, "D");
    try shift_layer.put(allocator, .ac04, "F");
    try shift_layer.put(allocator, .ac05, "G");
    try shift_layer.put(allocator, .ac06, "H");
    try shift_layer.put(allocator, .ac07, "J");
    try shift_layer.put(allocator, .ac08, "K");
    try shift_layer.put(allocator, .ac09, "L");
    try shift_layer.put(allocator, .ac10, ":");
    try shift_layer.put(allocator, .ac11, "*¨");
    try shift_layer.put(allocator, .bksl, "|");

    try shift_layer.put(allocator, .ab01, "Z");
    try shift_layer.put(allocator, .ab02, "X");
    try shift_layer.put(allocator, .ab03, "C");
    try shift_layer.put(allocator, .ab04, "V");
    try shift_layer.put(allocator, .ab05, "B");
    try shift_layer.put(allocator, .ab06, "N");
    try shift_layer.put(allocator, .ab07, "M");
    try shift_layer.put(allocator, .ab08, "<");
    try shift_layer.put(allocator, .ab09, ">");
    try shift_layer.put(allocator, .ab10, "?");

    try shift_layer.put(allocator, .spce, " ");

    var odk_layer = std.AutoHashMapUnmanaged(KeyCode, []const u8).empty;

    try odk_layer.put(allocator, .ae02, "«");
    try odk_layer.put(allocator, .ae03, "»");
    try odk_layer.put(allocator, .ae05, "€");

    try odk_layer.put(allocator, .ad03, "é");
    try odk_layer.put(allocator, .ad06, "ý");
    try odk_layer.put(allocator, .ad07, "ú");
    try odk_layer.put(allocator, .ad08, "í");
    try odk_layer.put(allocator, .ad09, "ó");

    try odk_layer.put(allocator, .ac01, "á");
    try odk_layer.put(allocator, .ac11, "'");

    try odk_layer.put(allocator, .ab03, "ç");
    try odk_layer.put(allocator, .ab07, "µ");
    try odk_layer.put(allocator, .ab08, "·");
    try odk_layer.put(allocator, .ab09, "…");

    try odk_layer.put(allocator, .spce, "'");

    var odk_shift_layer = std.AutoHashMapUnmanaged(KeyCode, []const u8).empty;

    try odk_shift_layer.put(allocator, .ae02, "«");
    try odk_shift_layer.put(allocator, .ae03, "»");
    try odk_shift_layer.put(allocator, .ae05, "€");

    try odk_shift_layer.put(allocator, .ad03, "É");
    try odk_shift_layer.put(allocator, .ad06, "Ý");
    try odk_shift_layer.put(allocator, .ad07, "Ú");
    try odk_shift_layer.put(allocator, .ad08, "Í");
    try odk_shift_layer.put(allocator, .ad09, "Ó");

    try odk_shift_layer.put(allocator, .ac01, "Á");
    try odk_shift_layer.put(allocator, .ac11, "'");

    try odk_shift_layer.put(allocator, .ab03, "Ç");
    try odk_shift_layer.put(allocator, .ab07, "Μ");
    try odk_shift_layer.put(allocator, .ab08, "•");
    try odk_shift_layer.put(allocator, .ab09, "…");

    try odk_shift_layer.put(allocator, .spce, "'");

    var altgr_layer = std.AutoHashMapUnmanaged(KeyCode, []const u8).empty;

    try altgr_layer.put(allocator, .tlde, "*`");
    try altgr_layer.put(allocator, .ae06, "*^");

    try altgr_layer.put(allocator, .ad01, "@");
    try altgr_layer.put(allocator, .ad02, "<");
    try altgr_layer.put(allocator, .ad03, ">");
    try altgr_layer.put(allocator, .ad04, "$");
    try altgr_layer.put(allocator, .ad05, "%");
    try altgr_layer.put(allocator, .ad06, "^");
    try altgr_layer.put(allocator, .ad07, "&");
    try altgr_layer.put(allocator, .ad08, "*");
    try altgr_layer.put(allocator, .ad09, "'");
    try altgr_layer.put(allocator, .ad10, "`");

    try altgr_layer.put(allocator, .ac01, "{");
    try altgr_layer.put(allocator, .ac02, "(");
    try altgr_layer.put(allocator, .ac03, ")");
    try altgr_layer.put(allocator, .ac04, "}");
    try altgr_layer.put(allocator, .ac05, "=");
    try altgr_layer.put(allocator, .ac06, "\\");
    try altgr_layer.put(allocator, .ac07, "+");
    try altgr_layer.put(allocator, .ac08, "-");
    try altgr_layer.put(allocator, .ac09, "/");
    try altgr_layer.put(allocator, .ac10, "\"");
    try altgr_layer.put(allocator, .ac11, "*´");

    try altgr_layer.put(allocator, .ab01, "~");
    try altgr_layer.put(allocator, .ab02, "[");
    try altgr_layer.put(allocator, .ab03, "]");
    try altgr_layer.put(allocator, .ab04, "_");
    try altgr_layer.put(allocator, .ab05, "#");
    try altgr_layer.put(allocator, .ab06, "|");
    try altgr_layer.put(allocator, .ab07, "!");
    try altgr_layer.put(allocator, .ab08, ";");
    try altgr_layer.put(allocator, .ab09, ":");
    try altgr_layer.put(allocator, .ab10, "?");

    try altgr_layer.put(allocator, .spce, " ");

    var altgr_shift_layer = std.AutoHashMapUnmanaged(KeyCode, []const u8).empty;

    try altgr_shift_layer.put(allocator, .tlde, "*~");
    try altgr_shift_layer.put(allocator, .ae06, "*^");

    try altgr_shift_layer.put(allocator, .ad01, "@");
    try altgr_shift_layer.put(allocator, .ad02, "<");
    try altgr_shift_layer.put(allocator, .ad03, ">");
    try altgr_shift_layer.put(allocator, .ad04, "$");
    try altgr_shift_layer.put(allocator, .ad05, "%");
    try altgr_shift_layer.put(allocator, .ad06, "^");
    try altgr_shift_layer.put(allocator, .ad07, "&");
    try altgr_shift_layer.put(allocator, .ad08, "*");
    try altgr_shift_layer.put(allocator, .ad09, "'");
    try altgr_shift_layer.put(allocator, .ad10, "`");

    try altgr_shift_layer.put(allocator, .ac01, "{");
    try altgr_shift_layer.put(allocator, .ac02, "(");
    try altgr_shift_layer.put(allocator, .ac03, ")");
    try altgr_shift_layer.put(allocator, .ac04, "}");
    try altgr_shift_layer.put(allocator, .ac05, "=");
    try altgr_shift_layer.put(allocator, .ac06, "\\");
    try altgr_shift_layer.put(allocator, .ac07, "+");
    try altgr_shift_layer.put(allocator, .ac08, "-");
    try altgr_shift_layer.put(allocator, .ac09, "/");
    try altgr_shift_layer.put(allocator, .ac10, "\"");
    try altgr_shift_layer.put(allocator, .ac11, "*¨");

    try altgr_shift_layer.put(allocator, .ab01, "~");
    try altgr_shift_layer.put(allocator, .ab02, "[");
    try altgr_shift_layer.put(allocator, .ab03, "]");
    try altgr_shift_layer.put(allocator, .ab04, "_");
    try altgr_shift_layer.put(allocator, .ab05, "#");
    try altgr_shift_layer.put(allocator, .ab06, "|");
    try altgr_shift_layer.put(allocator, .ab07, "!");
    try altgr_shift_layer.put(allocator, .ab08, ";");
    try altgr_shift_layer.put(allocator, .ab09, ":");
    try altgr_shift_layer.put(allocator, .ab10, "?");

    try altgr_shift_layer.put(allocator, .spce, " ");

    var layers = std.AutoHashMapUnmanaged(Layer, std.AutoHashMapUnmanaged(KeyCode, []const u8)).empty;

    try layers.put(allocator, .base, base_layer);
    try layers.put(allocator, .shift, shift_layer);
    try layers.put(allocator, .odk, odk_layer);
    try layers.put(allocator, .odk_shift, odk_shift_layer);
    try layers.put(allocator, .altgr, altgr_layer);
    try layers.put(allocator, .altgr_shift, altgr_shift_layer);

    return KeyboardLayout{
        .arena_allocator = arena.*,
        .name = "testlayout",
        .name8 = "testlayout",
        .locale = null,
        .variant = null,
        .author = null,
        .description = null,
        .url = null,
        .version = null,
        .geometry = .ISO,
        .layers = layers,
        .has_altgr = true,
        .has_1dk = true,
    };
}

test "getBase with 1dk" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);

    const keyboard_layout = try testInitKeyboardLayout(&arena);
    defer arena.deinit();

    const expected =
        \\┌─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┲━━━━━━━━━━┓
        \\│ ~   │ !   │ @   │ #   │ $   │ %   │ ^   │ &   │ *   │ (   │ )   │ _   │ +   ┃          ┃
        \\│ `   │ 1   │ 2 « │ 3 » │ 4   │ 5 € │ 6   │ 7   │ 8   │ 9   │ 0   │ -   │ =   ┃ ⌫        ┃
        \\┢━━━━━┷━━┱──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┺━━┳━━━━━━━┫
        \\┃        ┃ Q   │ W   │ E   │ R   │ T   │ Y   │ U   │ I   │ O   │ P   │ {   │ }   ┃       ┃
        \\┃ ↹      ┃     │     │   é │     │     │   ý │   ú │   í │   ó │     │ [   │ ]   ┃       ┃
        \\┣━━━━━━━━┻┱────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┺┓  ⏎   ┃
        \\┃         ┃ A   │ S   │ D   │ F   │ G   │ H   │ J   │ K   │ L   │ :   │*¨   │ |   ┃      ┃
        \\┃ ⇬       ┃   á │     │     │     │     │     │     │     │     │ ;   │** ' │ \   ┃      ┃
        \\┣━━━━━━┳━━┹──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┲━━┷━━━━━┻━━━━━━┫
        \\┃      ┃     │ Z   │ X   │ C   │ V   │ B   │ N   │ M Μ │ < • │ >   │ ?   ┃               ┃
        \\┃ ⇧    ┃     │     │     │   ç │     │     │     │   µ │ , · │ . … │ /   ┃ ⇧             ┃
        \\┣━━━━━━┻┳━━━━┷━━┳━━┷━━━━┱┴─────┴─────┴─────┴─────┴─────┴─┲━━━┷━━━┳━┷━━━━━╋━━━━━━━┳━━━━━━━┫
        \\┃       ┃       ┃       ┃                                ┃       ┃       ┃       ┃       ┃
        \\┃ Ctrl  ┃ super ┃ Alt   ┃ ␣                              ┃ AltGr ┃ super ┃ menu  ┃ Ctrl  ┃
        \\┗━━━━━━━┻━━━━━━━┻━━━━━━━┹────────────────────────────────┺━━━━━━━┻━━━━━━━┻━━━━━━━┻━━━━━━━┛
    ;

    const result = try getBase(std.testing.allocator, &keyboard_layout);
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings(expected, result);
}

test "getBase without 1dk" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);

    var keyboard_layout = try testInitKeyboardLayout(&arena);
    defer arena.deinit();

    keyboard_layout.has_1dk = false;

    const expected =
        \\┌─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┲━━━━━━━━━━┓
        \\│ ~   │ !   │ @   │ #   │ $   │ %   │ ^   │ &   │ *   │ (   │ )   │ _   │ +   ┃          ┃
        \\│ `   │ 1   │ 2   │ 3   │ 4   │ 5   │ 6   │ 7   │ 8   │ 9   │ 0   │ -   │ =   ┃ ⌫        ┃
        \\┢━━━━━┷━━┱──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┺━━┳━━━━━━━┫
        \\┃        ┃ Q   │ W   │ E   │ R   │ T   │ Y   │ U   │ I   │ O   │ P   │ {   │ }   ┃       ┃
        \\┃ ↹      ┃     │     │     │     │     │     │     │     │     │     │ [   │ ]   ┃       ┃
        \\┣━━━━━━━━┻┱────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┺┓  ⏎   ┃
        \\┃         ┃ A   │ S   │ D   │ F   │ G   │ H   │ J   │ K   │ L   │ :   │*¨   │ |   ┃      ┃
        \\┃ ⇬       ┃     │     │     │     │     │     │     │     │     │ ;   │**   │ \   ┃      ┃
        \\┣━━━━━━┳━━┹──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┲━━┷━━━━━┻━━━━━━┫
        \\┃      ┃     │ Z   │ X   │ C   │ V   │ B   │ N   │ M   │ <   │ >   │ ?   ┃               ┃
        \\┃ ⇧    ┃     │     │     │     │     │     │     │     │ ,   │ .   │ /   ┃ ⇧             ┃
        \\┣━━━━━━┻┳━━━━┷━━┳━━┷━━━━┱┴─────┴─────┴─────┴─────┴─────┴─┲━━━┷━━━┳━┷━━━━━╋━━━━━━━┳━━━━━━━┫
        \\┃       ┃       ┃       ┃                                ┃       ┃       ┃       ┃       ┃
        \\┃ Ctrl  ┃ super ┃ Alt   ┃ ␣                              ┃ AltGr ┃ super ┃ menu  ┃ Ctrl  ┃
        \\┗━━━━━━━┻━━━━━━━┻━━━━━━━┹────────────────────────────────┺━━━━━━━┻━━━━━━━┻━━━━━━━┻━━━━━━━┛
    ;

    const result = try getBase(std.testing.allocator, &keyboard_layout);
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings(expected, result);
}

test "getFull" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);

    var keyboard_layout = try testInitKeyboardLayout(&arena);
    defer arena.deinit();

    const expected =
        \\┌─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┲━━━━━━━━━━┓
        \\│ ~*~ │ !   │ @   │ #   │ $   │ %   │ ^   │ &   │ *   │ (   │ )   │ _   │ +   ┃          ┃
        \\│ `*` │ 1   │ 2   │ 3   │ 4   │ 5   │ 6*^ │ 7   │ 8   │ 9   │ 0   │ -   │ =   ┃ ⌫        ┃
        \\┢━━━━━┷━━┱──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┺━━┳━━━━━━━┫
        \\┃        ┃ Q   │ W   │ E   │ R   │ T   │ Y   │ U   │ I   │ O   │ P   │ {   │ }   ┃       ┃
        \\┃ ↹      ┃   @ │   < │   > │   $ │   % │   ^ │   & │   * │   ' │   ` │ [   │ ]   ┃       ┃
        \\┣━━━━━━━━┻┱────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┺┓  ⏎   ┃
        \\┃         ┃ A   │ S   │ D   │ F   │ G   │ H   │ J   │ K   │ L   │ :   │*¨*¨ │ |   ┃      ┃
        \\┃ ⇬       ┃   { │   ( │   ) │   } │   = │   \ │   + │   - │   / │ ; " │***´ │ \   ┃      ┃
        \\┣━━━━━━┳━━┹──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┲━━┷━━━━━┻━━━━━━┫
        \\┃      ┃     │ Z   │ X   │ C   │ V   │ B   │ N   │ M   │ <   │ >   │ ?   ┃               ┃
        \\┃ ⇧    ┃     │   ~ │   [ │   ] │   _ │   # │   | │   ! │ , ; │ . : │ / ? ┃ ⇧             ┃
        \\┣━━━━━━┻┳━━━━┷━━┳━━┷━━━━┱┴─────┴─────┴─────┴─────┴─────┴─┲━━━┷━━━┳━┷━━━━━╋━━━━━━━┳━━━━━━━┫
        \\┃       ┃       ┃       ┃                                ┃       ┃       ┃       ┃       ┃
        \\┃ Ctrl  ┃ super ┃ Alt   ┃ ␣                              ┃ AltGr ┃ super ┃ menu  ┃ Ctrl  ┃
        \\┗━━━━━━━┻━━━━━━━┻━━━━━━━┹────────────────────────────────┺━━━━━━━┻━━━━━━━┻━━━━━━━┻━━━━━━━┛
    ;

    const result = try getFull(std.testing.allocator, &keyboard_layout);
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings(expected, result);
}

test "getAltgr" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);

    var keyboard_layout = try testInitKeyboardLayout(&arena);
    defer arena.deinit();

    const expected =
        \\┌─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┲━━━━━━━━━━┓
        \\│  *~ │     │     │     │     │     │     │     │     │     │     │     │     ┃          ┃
        \\│  *` │     │     │     │     │     │  *^ │     │     │     │     │     │     ┃ ⌫        ┃
        \\┢━━━━━┷━━┱──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┺━━┳━━━━━━━┫
        \\┃        ┃     │     │     │     │     │     │     │     │     │     │     │     ┃       ┃
        \\┃ ↹      ┃   @ │   < │   > │   $ │   % │   ^ │   & │   * │   ' │   ` │     │     ┃       ┃
        \\┣━━━━━━━━┻┱────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┺┓  ⏎   ┃
        \\┃         ┃     │     │     │     │     │     │     │     │     │     │  *¨ │     ┃      ┃
        \\┃ ⇬       ┃   { │   ( │   ) │   } │   = │   \ │   + │   - │   / │   " │  *´ │     ┃      ┃
        \\┣━━━━━━┳━━┹──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┲━━┷━━━━━┻━━━━━━┫
        \\┃      ┃     │     │     │     │     │     │     │     │     │     │     ┃               ┃
        \\┃ ⇧    ┃     │   ~ │   [ │   ] │   _ │   # │   | │   ! │   ; │   : │   ? ┃ ⇧             ┃
        \\┣━━━━━━┻┳━━━━┷━━┳━━┷━━━━┱┴─────┴─────┴─────┴─────┴─────┴─┲━━━┷━━━┳━┷━━━━━╋━━━━━━━┳━━━━━━━┫
        \\┃       ┃       ┃       ┃                                ┃       ┃       ┃       ┃       ┃
        \\┃ Ctrl  ┃ super ┃ Alt   ┃ ␣                              ┃ AltGr ┃ super ┃ menu  ┃ Ctrl  ┃
        \\┗━━━━━━━┻━━━━━━━┻━━━━━━━┹────────────────────────────────┺━━━━━━━┻━━━━━━━┻━━━━━━━┻━━━━━━━┛
    ;

    const result = try getAltgr(std.testing.allocator, &keyboard_layout);
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings(expected, result);
}
