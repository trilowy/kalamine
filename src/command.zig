const std = @import("std");
const app = @import("build.zig.zon");
const Writer = std.Io.Writer;

pub fn version(writer: *Writer) !void {
    try writer.print("{s}\n", .{app.version});
    try writer.flush();
}
