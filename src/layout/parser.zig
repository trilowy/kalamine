const std = @import("std");
const Geometry = @import("layout.zig").Geometry;
const ParseOptions = @import("layout.zig").ParseOptions;
const ParsingError = @import("layout.zig").ParsingError;
const Diagnostic = @import("layout.zig").Diagnostic;
const Graphemes = @import("Graphemes");

/// Extract a keyboard layout
/// Caller is responsible of freeing memory
fn parseLayout(
    allocator: std.mem.Allocator,
    expected_geometry: Geometry,
    layout: []const u8,
    options: ParseOptions,
) !void {
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
            _ = keys;

            if (!std.mem.eql(u8, template_char, layout_char)) {
                // TODO: store chars but keep position in it
                // std.debug.print("empty_template: '{s}'\n", .{tc.bytes(empty_template)});
                std.debug.print("template_lines: '{s}'\n", .{layout_char});
                // TODO: create tests now
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

        if (std.mem.eql(u8, expected, "\n")) {
            diag.arg = "line return";
        } else {
            diag.arg = expected;
        }

        if (std.mem.eql(u8, found, "\n")) {
            diag.arg2 = "line return";
        } else {
            diag.arg2 = found;
        }
    }
    return ParsingError.WrongStructure;
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
    var diag = Diagnostic{};

    try parseLayout(std.testing.allocator, Geometry.ISO, layout, .{ .diagnostic = &diag });
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
    try std.testing.expectEqualStrings("line return", diag.arg);
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
    try std.testing.expectEqualStrings("line return", diag.arg);
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
    try std.testing.expectEqualStrings("line return", diag.arg);
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
    try std.testing.expectEqualStrings("line return", diag.arg2);
}
