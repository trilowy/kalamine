const std = @import("std");
const Geometry = @import("layout.zig").Geometry;
const error_handling = @import("../error_handling.zig");
const ParseOptions = error_handling.ParseOptions;
const Diagnostic = error_handling.Diagnostic;
const ParsingError = error_handling.ParsingError;
const KeyCode = @import("layout.zig").KeyCode;
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

/// Extract a keyboard layout
/// Caller is responsible of freeing memory
/// Inner character memory is bound to the layout parameter
pub fn parseLayout(
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

const expectEqualOptionalString = @import("../test/util.zig").expectEqualOptionalString;

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
