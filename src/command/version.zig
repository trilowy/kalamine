const std = @import("std");
const app = @import("build.zig.zon");

pub fn printTo(writer: *std.Io.Writer) !void {
    try writer.print("{s}\n", .{app.version});
    try writer.flush();
}
