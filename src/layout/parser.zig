const std = @import("std");
const Geometry = @import("layout.zig").Geometry;
const ParseOptions = @import("layout.zig").ParseOptions;
const ParsingError = @import("layout.zig").ParsingError;
const Diagnostic = @import("layout.zig").Diagnostic;
const KeyCode = @import("layout.zig").KeyCode;
const Graphemes = @import("Graphemes");

pub const ParsedKey = struct {
    left_up: ?[]const u8 = null,
    left_down: ?[]const u8 = null,
    right_up: ?[]const u8 = null,
    right_down: ?[]const u8 = null,
};

/// Extract a keyboard layout
/// Caller is responsible of freeing memory
/// Inner character memory is bound to the layout parameter
fn parseLayout(
    allocator: std.mem.Allocator,
    expected_geometry: Geometry,
    layout: []const u8,
    options: ParseOptions,
) !std.AutoHashMapUnmanaged(KeyCode, ParsedKey) {
    // TODO: loop on empty template and filled template
    // https://codeberg.org/atman/zg#grapheme-clusters
    // Loop once per TOML entry and return a structure of keys with 4 possible values
    // Loop on this structure and copy wath is needed (and shift rule) and deinit arena of structure
    // TODO: check if 2 kinds of "é" can be compared
    // TODO: rows mandatory to know the offset? avoid chars in layout in wrong key?
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

    // TODO: line of the TOML is better for the feedback
    var line: usize = 1;
    var column: usize = 1;

    // Skip the first line return
    if (layout_iter.next()) |lc| {
        if (!std.mem.eql(u8, "\n", lc.bytes(layout))) {
            return wrongStructureError(line, column, "\n", lc.bytes(layout), options);
        }
    }

    while (template_iter.next()) |tc| : (column += 1) {
        if (layout_iter.next()) |lc| {
            const template_char = tc.bytes(template);
            const layout_char = lc.bytes(layout);

            // Empty template and parsed template should have same structure
            if (!std.mem.eql(u8, template_char, " ")) {
                if (std.mem.eql(u8, template_char, layout_char)) {
                    if (std.mem.eql(u8, template_char, "\n")) {
                        line += 1;
                        column = 0; // Because autoincrement at the end of iteration
                    }
                } else {
                    return wrongStructureError(line, column, template_char, layout_char, options);
                }
            }

            // TODO: no char in offset or outside keys
            // mod of line for keycode row
            // * or space for first char
            // something mandatory following * of dead key
            // replace existing str if * present when reading second char, or error if space (on column or col - 1?)

            if (!std.mem.eql(u8, template_char, layout_char)) {
                // TODO: store chars but keep position in it
                std.debug.print("layout_char: '{s}'\n", .{layout_char});
            }
        } else {
            // Template has characters but not the layout
            return wrongStructureError(line, column, tc.bytes(template), "nothing", options);
        }
    }

    // Skip the last line return
    if (layout_iter.next()) |lc| {
        if (!std.mem.eql(u8, "\n", lc.bytes(layout))) {
            return wrongStructureError(line, column, "\n", lc.bytes(layout), options);
        }
        line += 1;
        column = 1;
    } else {
        return wrongStructureError(line, column, "\n", "nothing", options);
    }

    if (layout_iter.next()) |lc| {
        // Layout has characters but not the template
        return wrongStructureError(line, column, "nothing", lc.bytes(layout), options);
    }

    return keymap;
}

fn wrongStructureError(
    line: usize,
    column: usize,
    expected: []const u8,
    found: []const u8,
    options: ParseOptions,
) ParsingError {
    if (options.diagnostic) |diag| {
        diag.line = line;
        diag.column = column;
        diag.arg = replaceInvisibleCharInError(expected);
        diag.arg2 = replaceInvisibleCharInError(found);
    }
    return ParsingError.WrongStructure;
}

fn replaceInvisibleCharInError(to_replace: []const u8) []const u8 {
    if (std.mem.eql(u8, to_replace, "\n")) {
        return "a line return";
    }
    if (std.mem.eql(u8, to_replace, "\t")) {
        return "a tabulation";
    }
    if (std.mem.eql(u8, to_replace, " ")) {
        return "a space";
    }
    return to_replace;
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

    var diag = Diagnostic{};
    const result = parseLayout(std.testing.allocator, Geometry.ISO, layout, .{ .diagnostic = &diag });

    try std.testing.expectEqual(ParsingError.WrongStructure, result);
    try std.testing.expectEqual(1, diag.line);
    try std.testing.expectEqual(1, diag.column);
    try std.testing.expectEqualStrings("a line return", diag.arg);
    try std.testing.expectEqualStrings("┌", diag.arg2);
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

    var diag = Diagnostic{};
    const result = parseLayout(std.testing.allocator, Geometry.ISO, layout, .{ .diagnostic = &diag });

    try std.testing.expectEqual(ParsingError.WrongStructure, result);
    try std.testing.expectEqual(16, diag.line);
    try std.testing.expectEqual(91, diag.column);
    try std.testing.expectEqualStrings("a line return", diag.arg);
    try std.testing.expectEqualStrings("nothing", diag.arg2);
}

test "parseLayout truncated layout" {
    const layout =
        \\
        \\┌─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┲━━━━━━━━━━┓
        \\
    ;

    var diag = Diagnostic{};
    const result = parseLayout(std.testing.allocator, Geometry.ISO, layout, .{ .diagnostic = &diag });

    try std.testing.expectEqual(ParsingError.WrongStructure, result);
    try std.testing.expectEqual(2, diag.line);
    try std.testing.expectEqual(1, diag.column);
    try std.testing.expectEqualStrings("│", diag.arg);
    try std.testing.expectEqualStrings("nothing", diag.arg2);
}

test "parseLayout truncated layout line return" {
    const layout =
        \\
        \\┌─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┲━━━━━━━━━━┓
    ;

    var diag = Diagnostic{};
    const result = parseLayout(std.testing.allocator, Geometry.ISO, layout, .{ .diagnostic = &diag });

    try std.testing.expectEqual(ParsingError.WrongStructure, result);
    try std.testing.expectEqual(1, diag.line);
    try std.testing.expectEqual(91, diag.column);
    try std.testing.expectEqualStrings("a line return", diag.arg);
    try std.testing.expectEqualStrings("nothing", diag.arg2);
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

    var diag = Diagnostic{};
    const result = parseLayout(std.testing.allocator, Geometry.ISO, layout, .{ .diagnostic = &diag });

    try std.testing.expectEqual(ParsingError.WrongStructure, result);
    try std.testing.expectEqual(17, diag.line);
    try std.testing.expectEqual(1, diag.column);
    try std.testing.expectEqualStrings("nothing", diag.arg);
    try std.testing.expectEqualStrings("a", diag.arg2);
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

    var diag = Diagnostic{};
    const result = parseLayout(std.testing.allocator, Geometry.ISO, layout, .{ .diagnostic = &diag });

    try std.testing.expectEqual(ParsingError.WrongStructure, result);
    try std.testing.expectEqual(17, diag.line);
    try std.testing.expectEqual(1, diag.column);
    try std.testing.expectEqualStrings("nothing", diag.arg);
    try std.testing.expectEqualStrings("a line return", diag.arg2);
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

    var diag = Diagnostic{};
    const result = parseLayout(std.testing.allocator, Geometry.ISO, layout, .{ .diagnostic = &diag });

    try std.testing.expectEqual(ParsingError.WrongStructure, result);
    try std.testing.expectEqual(1, diag.line);
    try std.testing.expectEqual(1, diag.column);
    try std.testing.expectEqualStrings("┌", diag.arg);
    try std.testing.expectEqualStrings("a space", diag.arg2);
}

test "parseLayout wrong indentation with tab" {
    const layout = "\n\t┌─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┲━━━━━━━━━━┓";

    var diag = Diagnostic{};
    const result = parseLayout(std.testing.allocator, Geometry.ISO, layout, .{ .diagnostic = &diag });

    try std.testing.expectEqual(ParsingError.WrongStructure, result);
    try std.testing.expectEqual(1, diag.line);
    try std.testing.expectEqual(1, diag.column);
    try std.testing.expectEqualStrings("┌", diag.arg);
    try std.testing.expectEqualStrings("a tabulation", diag.arg2);
}
