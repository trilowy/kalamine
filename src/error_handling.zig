const std = @import("std");

pub const ParseOptions = struct {
    diagnostic: ?*Diagnostic = null,
};

pub const Diagnostic = struct {
    // FIXME: error cannot be reported in higher call if expected/found is on the stack
    // maybe keep the whole message in memory? deinit when reported
    arg: []const u8 = "",
    line: usize = 0,
    column: usize = 0,
    expected: []const u8 = "",
    found: []const u8 = "",

    pub fn report(self: Diagnostic, writer: *std.Io.Writer, err: anyerror) anyerror {
        switch (err) {
            ParsingError.MissingAttribute => {
                try writer.print("kalamine: parse error: missing mandatory '{s}' attribute\n", .{self.arg});
                try writer.flush();
                return error.ErrorReported;
            },
            ParsingError.MissingLayout => {
                try writer.writeAll("kalamine: parse error: missing mandatory layout 'full' or 'base'\n");
                try writer.flush();
                return error.ErrorReported;
            },
            // TODO: see if it is still useful
            ParsingError.WrongValue => {
                try writer.print("kalamine: parse error: wrong value in layout '{s}', line {d}, column {d}\n", .{ self.arg, self.line, self.column });
                try writer.flush();
                return error.ErrorReported;
            },
            ParsingError.WrongStructure => {
                try writer.print(
                    \\kalamine: parse error: wrong structure in layout '{s}', line {d}, column {d}
                    \\Expected: {s} found: {s}
                    \\See how the layout should be structured with the 'new' command
                    \\
                , .{ self.arg, self.line, self.column, self.expected, self.found });
                try writer.flush();
                return error.ErrorReported;
            },
            ParsingError.CharAtBadPlace => {
                try writer.print(
                    \\kalamine: parse error: a character is in the wrong key in layout '{s}', line {d}, column {d}
                    \\Expected: {s} found: {s}
                    \\See how the layout should be structured with the 'new' command
                    \\
                , .{ self.arg, self.line, self.column, self.expected, self.found });
                try writer.flush();
                return error.ErrorReported;
            },
            else => return err,
        }
    }
};

pub const ParsingError = error{
    MissingAttribute,
    MissingLayout,
    WrongValue,
    WrongStructure,
    CharAtBadPlace,
};
