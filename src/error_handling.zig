const std = @import("std");

pub const ParseOptions = struct {
    diagnostic: ?*Diagnostic = null,

    pub fn setParsingError(
        self: ParseOptions,
        err: ParsingError,
        line: usize,
        column: usize,
        expected: []const u8,
        found: []const u8,
    ) ParsingError {
        if (self.diagnostic) |diag| {
            diag.setParsingError(line, column, expected, found);
        }
        return err;
    }
};

pub const Diagnostic = struct {
    allocator: std.mem.Allocator,
    arg: []const u8 = "",
    line: usize = 0,
    column: usize = 0,
    expected: ?[]const u8 = null,
    found: ?[]const u8 = null,

    pub fn deinit(self: *Diagnostic) void {
        if (self.expected) |expected| {
            self.allocator.free(expected);
            self.expected = null;
        }
        if (self.found) |found| {
            self.allocator.free(found);
            self.found = null;
        }
    }

    pub fn setParsingError(
        self: *Diagnostic,
        line: usize,
        column: usize,
        expected: []const u8,
        found: []const u8,
    ) void {
        // TODO: change line number according to the field in error in TOML (might have to write a TOML lib for that)
        self.line = line;
        self.column = column;
        // Allocator to make the error strings go up in the stack (avoid dangling pointer)
        self.expected = self.allocator.dupe(u8, replaceInvisibleCharInError(expected)) catch @panic("Out of memory");
        self.found = self.allocator.dupe(u8, replaceInvisibleCharInError(found)) catch @panic("Out of memory");
    }

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
                    \\See how the layout should be structured with the 'new' command and check your geometry
                    \\
                , .{ self.arg, self.line, self.column, self.expected orelse "", self.found orelse "" });
                try writer.flush();
                return error.ErrorReported;
            },
            ParsingError.CharAtBadPlace => {
                try writer.print(
                    \\kalamine: parse error: a character is in the wrong place in layout '{s}', line {d}, column {d}
                    \\Expected: {s} found: {s}
                    \\See how the layout should be structured with the 'new' command and check your geometry
                    \\
                , .{ self.arg, self.line, self.column, self.expected orelse "", self.found orelse "" });
                try writer.flush();
                return error.ErrorReported;
            },
            else => return err,
        }
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
};

pub const ParsingError = error{
    MissingAttribute,
    MissingLayout,
    WrongValue,
    WrongStructure,
    CharAtBadPlace,
};
