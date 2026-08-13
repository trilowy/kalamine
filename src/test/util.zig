const std = @import("std");

pub fn expectEqualOptionalString(maybe_expected: ?[]const u8, maybe_actual: ?[]const u8) !void {
    if (maybe_expected) |expected| {
        try std.testing.expect(maybe_actual != null);
        try std.testing.expectEqualStrings(expected, maybe_actual.?);
    } else {
        try std.testing.expect(maybe_actual == null);
    }
}
