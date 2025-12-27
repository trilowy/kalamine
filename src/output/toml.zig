//! Output a keyboard layout to TOML representation

const std = @import("std");
const layout = @import("../layout/layout.zig");
const Layer = layout.Layer;

/// Base + 1dk layers
pub fn getBase(allocator: std.mem.Allocator, keyboard_layout: *const layout.KeyboardLayout) ![]u8 {
    const layers = [_]Layer{ Layer.base, Layer.odk };
    return getGeometry(allocator, keyboard_layout, &layers);
}

/// Base + 1dk layers
pub fn getAltgr(allocator: std.mem.Allocator, keyboard_layout: *const layout.KeyboardLayout) ![]u8 {
    const layers = [_]Layer{Layer.altgr};
    return getGeometry(allocator, keyboard_layout, &layers);
}

/// Geometry view of the requested layers
fn getGeometry(allocator: std.mem.Allocator, keyboard_layout: *const layout.KeyboardLayout, layers: []const Layer) ![]u8 {
    const rows = keyboard_layout.geometry.getKeys();
    const template = keyboard_layout.geometry.getTemplate();

    const template_to_fill = try allocator.dupe(u8, template);

    for (layers) |layer| {
        fillTemplate(template_to_fill, keyboard_layout, rows, layer);
    }

    return template_to_fill;
}

/// Fill a template with a keyboard layer
fn fillTemplate(template_lines: []u8, keyboard_layout: *const layout.KeyboardLayout, rows: [4]layout.RowDescription, layer: Layer) void {
    var template = std.mem.splitScalar(u8, template_lines, '\n');

    const col_offset: usize, const shift_prevails = if (layer == Layer.base) .{ 0, true } else .{ 2, false };

    var j: usize = 0;

    for (rows) |row| {
        defer j += 1;

        // Should never be null because we set ourselve the template in this program
        _ = template.next() orelse unreachable;

        var i = row.offset + col_offset;

        const shift = template.next().?;
        const base = template.next().?;

        for (row.keys) |key| {
            defer i += 6;
            // TODO: kalamine/layout.py:343
            _ = keyboard_layout;
            _ = shift_prevails;
            _ = shift;
            _ = base;
            _ = key;
        }
    }
}
