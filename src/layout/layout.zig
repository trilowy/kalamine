const std = @import("std");
const toml = @import("toml");
const LetterCasing = @import("LetterCasing");
const Graphemes = @import("Graphemes");

pub const Geometry = enum {
    ISO,
    ANSI,
    ERGO,
    ABNT,
    JIS,
    ALT,

    pub fn getTemplate(self: Geometry) []const u8 {
        return switch (self) {
            .ISO => iso_template,
            .ANSI => ansi_template,
            .ERGO => ergo_template,
            .ABNT => abnt_template,
            .JIS => jis_template,
            .ALT => alt_template,
        };
    }

    pub fn getKeys(self: Geometry) [4]RowDescription {
        return switch (self) {
            .ISO => iso_rows,
            .ANSI => ansi_rows,
            .ERGO => ergo_rows,
            .ABNT => abnt_rows,
            .JIS => jis_rows,
            .ALT => alt_rows,
        };
    }
};

pub const Layer = enum {
    base,
    shift,
    odk,
    odk_shift,
    altgr,
    altgr_shift,

    fn shifted(self: Layer) Layer {
        return switch (self) {
            .base => .shift,
            .shift => .shift,
            .odk => .odk_shift,
            .odk_shift => .odk_shift,
            .altgr => .altgr_shift,
            .altgr_shift => .altgr_shift,
        };
    }
};
// TODO: if needed: @intFromEnum(Layer.base)

const TomlContent = struct {
    name: ?[]const u8,
    name8: ?[]const u8,
    locale: ?[]const u8,
    variant: ?[]const u8,
    author: ?[]const u8,
    description: ?[]const u8,
    url: ?[]const u8,
    version: ?[]const u8,
    geometry: ?Geometry,
    base: ?[]const u8,
    full: ?[]const u8,
    altgr: ?[]const u8,
};

pub const ParseOptions = struct {
    diagnostic: ?*Diagnostic = null,
};

pub const Diagnostic = struct {
    arg: []const u8 = "",
    arg2: []const u8 = "",
    line: usize = 0,
    column: usize = 0,

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
                , .{ self.arg, self.line, self.column, self.arg, self.arg2 });
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
};

pub const KeyboardLayout = struct {
    // TODO: kalamine/layout.py:142

    /// Store all values
    arena_allocator: std.heap.ArenaAllocator,

    /// Full layout name, displayed in the keyboard settings
    name: []const u8,
    /// Short Windows filename: no spaces, no special chars
    name8: []const u8,
    /// Locale/language ID
    locale: ?[]const u8,
    /// Layout variant ID
    variant: ?[]const u8,
    /// Author name
    author: ?[]const u8,
    description: ?[]const u8,
    url: ?[]const u8,
    version: ?[]const u8,
    geometry: Geometry,
    layers: std.AutoHashMapUnmanaged(Layer, std.AutoHashMapUnmanaged(KeyCode, []u8)),
    has_altgr: bool = false,
    has_1dk: bool = false,

    /// Deinitialize with `deinit`
    /// In case of error, deinitialize the error message if present in options
    pub fn initFromToml(
        allocator: std.mem.Allocator,
        reader: *std.Io.Reader,
        options: ParseOptions,
    ) !KeyboardLayout {
        // Read all
        const toml_content: []const u8 = try reader.allocRemaining(allocator, .unlimited);
        defer allocator.free(toml_content);

        // Parse TOML
        var toml_parser = toml.Parser(TomlContent).init(allocator);
        defer toml_parser.deinit();

        var result = try toml_parser.parseString(toml_content);
        defer result.deinit();

        const parsed_toml = result.value;

        var arena_allocator = std.heap.ArenaAllocator.init(allocator);
        const arena = arena_allocator.allocator();
        errdefer arena_allocator.deinit();

        // Own the memory of each field to free the rest
        const name = if (parsed_toml.name) |name|
            try arena.dupe(u8, name)
        else {
            if (options.diagnostic) |diag| diag.arg = "name";
            return ParsingError.MissingAttribute;
        };

        const name8 = if (parsed_toml.name8) |name8|
            try arena.dupe(u8, name8)
        else
            try arena.dupe(u8, name[0..8]);

        const locale = if (parsed_toml.locale) |locale|
            try arena.dupe(u8, locale)
        else
            null;

        const variant = if (parsed_toml.variant) |variant|
            try arena.dupe(u8, variant)
        else
            null;

        const author = if (parsed_toml.author) |author|
            try arena.dupe(u8, author)
        else
            null;

        const description = if (parsed_toml.description) |description|
            try arena.dupe(u8, description)
        else
            null;

        const url = if (parsed_toml.url) |url|
            try arena.dupe(u8, url)
        else
            null;

        const version = if (parsed_toml.version) |version|
            try arena.dupe(u8, version)
        else
            null;

        const geometry = if (parsed_toml.geometry) |geometry|
            geometry
        else {
            if (options.diagnostic) |diag| diag.arg = "geometry";
            return ParsingError.MissingAttribute;
        };

        var layers = std.AutoHashMapUnmanaged(Layer, std.AutoHashMapUnmanaged(KeyCode, []u8)).empty;
        for (std.enums.values(Layer)) |layer| {
            try layers.put(arena, layer, std.AutoHashMapUnmanaged(KeyCode, []u8).empty);
        }

        var keyboard_layout = KeyboardLayout{
            .arena_allocator = arena_allocator,
            .name = name,
            .name8 = name8,
            .locale = locale,
            .variant = variant,
            .author = author,
            .description = description,
            .url = url,
            .version = version,
            .geometry = geometry,
            .layers = layers,
        };

        const rows = keyboard_layout.geometry.getKeys();

        if (parsed_toml.full) |full_to_parse| {
            if (options.diagnostic) |diag| diag.arg = "full";
            try keyboard_layout.parseTemplate(allocator, full_to_parse, &rows, Layer.base, options);
            try keyboard_layout.parseTemplate(allocator, full_to_parse, &rows, Layer.altgr, options);
            keyboard_layout.has_altgr = true;
            if (options.diagnostic) |diag| diag.arg = "";
        } else if (parsed_toml.base) |base_to_parse| {
            if (options.diagnostic) |diag| diag.arg = "base";
            try keyboard_layout.parseTemplate(allocator, base_to_parse, &rows, Layer.base, options);
            try keyboard_layout.parseTemplate(allocator, base_to_parse, &rows, Layer.odk, options);

            if (parsed_toml.altgr) |altgr_to_parse| {
                if (options.diagnostic) |diag| diag.arg = "altgr";
                try keyboard_layout.parseTemplate(allocator, altgr_to_parse, &rows, Layer.altgr, options);
                keyboard_layout.has_altgr = true;
            }
            if (options.diagnostic) |diag| diag.arg = "";
        } else {
            return ParsingError.MissingLayout;
        }

        // TODO: kalamine/layout.py:192
        // all other missing features like space bar or angle-mod

        return keyboard_layout;
    }

    pub fn deinit(self: *KeyboardLayout) void {
        self.arena_allocator.deinit();
        self.* = undefined;
    }

    /// Extract a keyboard layer from a template
    fn parseTemplate(
        self: *KeyboardLayout,
        allocator: std.mem.Allocator,
        template_lines: []const u8,
        rows: []const RowDescription,
        layer: Layer,
        options: ParseOptions,
    ) !void {
        var template = std.mem.splitScalar(u8, template_lines, '\n');
        const arena = self.arena_allocator.allocator();

        const case = try LetterCasing.init(allocator);
        defer case.deinit(allocator);

        var j: usize = 0;
        const col_offset: usize = if (layer == .base) 0 else 2;

        for (rows) |row| {
            defer j += 1;

            if (template.next() == null) {
                if (options.diagnostic) |diag| diag.line = j;
                return ParsingError.WrongValue;
            }

            var i = row.offset + col_offset;

            const shift = if (template.next()) |line| line else {
                if (options.diagnostic) |diag| diag.line = j + 1;
                return ParsingError.WrongValue;
            };

            const base = if (template.next()) |line| line else {
                if (options.diagnostic) |diag| diag.line = j + 2;
                return ParsingError.WrongValue;
            };

            for (row.keys) |key| {
                // TODO: 6 by 6 grapheme clusters
                // https://codeberg.org/atman/zg#grapheme-clusters
                defer i += 6;

                const base_key = if (base[i - 1] == '*')
                    base[(i - 1)..(i + 1)]
                else
                    base[i..(i + 1)];

                const shift_key = if (base[i - 1] == '*')
                    shift[(i - 1)..(i + 1)]
                else
                    shift[i..(i + 1)];

                // In the base layer, if the base character is undefined, shift prevails
                if (layer == .base and
                    std.mem.eql(u8, base_key, " ") and
                    !std.mem.eql(u8, shift_key, " "))
                {
                    const base_key_to_put = try case.toLowerStr(arena, shift_key);
                    var layer_map = self.layers.get(layer).?;
                    try layer_map.put(arena, key, base_key_to_put);

                    const shift_key_to_put = try arena.dupe(u8, shift_key);
                    var shifted_layer_map = self.layers.get(layer.shifted()).?;
                    try shifted_layer_map.put(arena, key, shift_key_to_put);
                }
                // In other layers, if the shift character is undefined, base prevails
                else if ((layer == .altgr or layer == .odk) and
                    std.mem.eql(u8, shift_key, " ") and
                    !std.mem.eql(u8, base_key, " "))
                {
                    const base_key_to_put = try arena.dupe(u8, base_key);
                    var layer_map = self.layers.get(layer).?;
                    try layer_map.put(arena, key, base_key_to_put);

                    const shift_key_to_put = try case.toUpperStr(arena, base_key);
                    var shifted_layer_map = self.layers.get(layer.shifted()).?;
                    try shifted_layer_map.put(arena, key, shift_key_to_put);
                } else {
                    if (!std.mem.eql(u8, base_key, " ")) {
                        const base_key_to_put = try arena.dupe(u8, base_key);
                        var layer_map = self.layers.get(layer).?;
                        try layer_map.put(arena, key, base_key_to_put);
                    }

                    if (!std.mem.eql(u8, shift_key, " ")) {
                        const shift_key_to_put = try arena.dupe(u8, shift_key);
                        var shifted_layer_map = self.layers.get(layer).?;
                        try shifted_layer_map.put(arena, key, shift_key_to_put);
                    }
                }

                // TODO: kalamine/layout.py:311
                // dead_keys set
            }
        }
    }

    // TODO: kalamine/layout.py:403
    // _get_geometry / _fill_template
};

// TODO: kalamine/layout.py:276
// parse template the same as python version? how to make it more robust?
// better parsing error message?
// parse first the template to see if it matches perfectly first?
// tips of why it might not match: spaces at the beginning of the line
// row and column where it does not match

pub const RowDescription = struct {
    offset: usize,
    keys: []const KeyCode,
};

pub const KeyCode = enum {
    ab01,
    ab02,
    ab03,
    ab04,
    ab05,
    ab06,
    ab07,
    ab08,
    ab09,
    ab10,
    ab11,
    ac01,
    ac02,
    ac03,
    ac04,
    ac05,
    ac06,
    ac07,
    ac08,
    ac09,
    ac10,
    ac11,
    ad01,
    ad02,
    ad03,
    ad04,
    ad05,
    ad06,
    ad07,
    ad08,
    ad09,
    ad10,
    ad11,
    ad12,
    ae01,
    ae02,
    ae03,
    ae04,
    ae05,
    ae06,
    ae07,
    ae08,
    ae09,
    ae10,
    ae11,
    ae12,
    ae13,
    bksl,
    lsgt,
    tlde,
};

const iso_template =
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

const iso_rows = [_]RowDescription{
    .{
        .offset = 1,
        .keys = &[_]KeyCode{ .tlde, .ae01, .ae02, .ae03, .ae04, .ae05, .ae06, .ae07, .ae08, .ae09, .ae10, .ae11, .ae12 },
    },
    .{
        .offset = 10,
        .keys = &[_]KeyCode{ .ad01, .ad02, .ad03, .ad04, .ad05, .ad06, .ad07, .ad08, .ad09, .ad10, .ad11, .ad12 },
    },
    .{
        .offset = 11,
        .keys = &[_]KeyCode{ .ac01, .ac02, .ac03, .ac04, .ac05, .ac06, .ac07, .ac08, .ac09, .ac10, .ac11, .bksl },
    },
    .{
        .offset = 8,
        .keys = &[_]KeyCode{ .lsgt, .ab01, .ab02, .ab03, .ab04, .ab05, .ab06, .ab07, .ab08, .ab09, .ab10 },
    },
};

const ansi_template =
    \\┌─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┲━━━━━━━━━━┓
    \\│     │     │     │     │     │     │     │     │     │     │     │     │     ┃          ┃
    \\│     │     │     │     │     │     │     │     │     │     │     │     │     ┃ ⌫        ┃
    \\┢━━━━━┷━━┱──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┺━━┯━━━━━━━┩
    \\┃        ┃     │     │     │     │     │     │     │     │     │     │     │     │       │
    \\┃ ↹      ┃     │     │     │     │     │     │     │     │     │     │     │     │       │
    \\┣━━━━━━━━┻┱────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┲━━━━┷━━━━━━━┪
    \\┃         ┃     │     │     │     │     │     │     │     │     │     │     ┃            ┃
    \\┃ ⇬       ┃     │     │     │     │     │     │     │     │     │     │     ┃ ⏎          ┃
    \\┣━━━━━━━━━┻━━┱──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┲━━┻━━━━━━━━━━━━┫
    \\┃            ┃     │     │     │     │     │     │     │     │     │     ┃               ┃
    \\┃ ⇧          ┃     │     │     │     │     │     │     │     │     │     ┃ ⇧             ┃
    \\┣━━━━━━━┳━━━━┻━━┳━━┷━━━━┱┴─────┴─────┴─────┴─────┴─────┴─┲━━━┷━━━┳━┷━━━━━╋━━━━━━━┳━━━━━━━┫
    \\┃       ┃       ┃       ┃                                ┃       ┃       ┃       ┃       ┃
    \\┃ Ctrl  ┃ super ┃ Alt   ┃ ␣                              ┃ Alt   ┃ super ┃ menu  ┃ Ctrl  ┃
    \\┗━━━━━━━┻━━━━━━━┻━━━━━━━┹────────────────────────────────┺━━━━━━━┻━━━━━━━┻━━━━━━━┻━━━━━━━┛
;

const ansi_rows = [_]RowDescription{
    .{
        .offset = 1,
        .keys = &[_]KeyCode{ .tlde, .ae01, .ae02, .ae03, .ae04, .ae05, .ae06, .ae07, .ae08, .ae09, .ae10, .ae11, .ae12 },
    },
    .{
        .offset = 10,
        .keys = &[_]KeyCode{ .ad01, .ad02, .ad03, .ad04, .ad05, .ad06, .ad07, .ad08, .ad09, .ad10, .ad11, .ad12, .bksl },
    },
    .{
        .offset = 11,
        .keys = &[_]KeyCode{ .ac01, .ac02, .ac03, .ac04, .ac05, .ac06, .ac07, .ac08, .ac09, .ac10, .ac11 },
    },
    .{
        .offset = 14,
        .keys = &[_]KeyCode{ .ab01, .ab02, .ab03, .ab04, .ab05, .ab06, .ab07, .ab08, .ab09, .ab10 },
    },
};

const ergo_template =
    \\╭╌╌╌╌╌┰─────┬─────┬─────┬─────┬─────┰─────┬─────┬─────┬─────┬─────┰╌╌╌╌╌┬╌╌╌╌╌╮
    \\┆     ┃     │     │     │     │     ┃     │     │     │     │     ┃     ┆     ┆
    \\┆     ┃     │     │     │     │     ┃     │     │     │     │     ┃     ┆     ┆
    \\╰╌╌╌╌╌╂─────┼─────┼─────┼─────┼─────╂─────┼─────┼─────┼─────┼─────╂╌╌╌╌╌┼╌╌╌╌╌┤
    \\      ┃     │     │     │     │     ┃     │     │     │     │     ┃     ┆     ┆
    \\      ┃     │     │     │     │     ┃     │     │     │     │     ┃     ┆     ┆
    \\      ┠─────┼─────┼─────┼─────┼─────╂─────┼─────┼─────┼─────┼─────╂╌╌╌╌╌┼╌╌╌╌╌┤
    \\      ┃     │     │     │     │     ┃     │     │     │     │     ┃     ┆     ┆
    \\      ┃     │     │     │     │     ┃     │     │     │     │     ┃     ┆     ┆
    \\╭╌╌╌╌╌╂─────┼─────┼─────┼─────┼─────╂─────┼─────┼─────┼─────┼─────╂╌╌╌╌╌┴╌╌╌╌╌╯
    \\┆     ┃     │     │     │     │     ┃     │     │     │     │     ┃
    \\┆     ┃     │     │     │     │     ┃     │     │     │     │     ┃
    \\╰╌╌╌╌╌┸─────┴─────┴─────┴─────┴─────┸─────┴─────┴─────┴─────┴─────┚
;

const ergo_rows = [_]RowDescription{
    .{
        .offset = 1,
        .keys = &[_]KeyCode{ .tlde, .ae01, .ae02, .ae03, .ae04, .ae05, .ae06, .ae07, .ae08, .ae09, .ae10, .ae11, .ae12 },
    },
    .{
        .offset = 7,
        .keys = &[_]KeyCode{ .ad01, .ad02, .ad03, .ad04, .ad05, .ad06, .ad07, .ad08, .ad09, .ad10, .ad11, .ad12 },
    },
    .{
        .offset = 7,
        .keys = &[_]KeyCode{ .ac01, .ac02, .ac03, .ac04, .ac05, .ac06, .ac07, .ac08, .ac09, .ac10, .ac11, .bksl },
    },
    .{
        .offset = 1,
        .keys = &[_]KeyCode{ .lsgt, .ab01, .ab02, .ab03, .ab04, .ab05, .ab06, .ab07, .ab08, .ab09, .ab10 },
    },
};

const abnt_template =
    \\┌─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┲━━━━━━━━━━┓
    \\│     │     │     │     │     │     │     │     │     │     │     │     │     ┃          ┃
    \\│     │     │     │     │     │     │     │     │     │     │     │     │     ┃ ⌫        ┃
    \\┢━━━━━┷━━┱──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┺━━┳━━━━━━━┫
    \\┃        ┃     │     │     │     │     │     │     │     │     │     │     │     ┃       ┃
    \\┃ ↹      ┃     │     │     │     │     │     │     │     │     │     │     │     ┃       ┃
    \\┣━━━━━━━━┻┱────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┺┓  ⏎   ┃
    \\┃         ┃     │     │     │     │     │     │     │     │     │     │     │     ┃      ┃
    \\┃ ⇬       ┃     │     │     │     │     │     │     │     │     │     │     │     ┃      ┃
    \\┣━━━━━━┳━━┹──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┲━━┻━━━━━━┫
    \\┃      ┃     │     │     │     │     │     │     │     │     │     │     │     ┃         ┃
    \\┃ ⇧    ┃     │     │     │     │     │     │     │     │     │     │     │     ┃ ⇧       ┃
    \\┣━━━━━━┻┳━━━━┷━━┳━━┷━━━━┱┴─────┴─────┴─────┴─────┴─────┴─┲━━━┷━━━┳━┷━━━━━╈━━━━━┻━┳━━━━━━━┫
    \\┃       ┃       ┃       ┃                                ┃       ┃       ┃       ┃       ┃
    \\┃ Ctrl  ┃ super ┃ Alt   ┃ ␣                              ┃ AltGr ┃ super ┃ menu  ┃ Ctrl  ┃
    \\┗━━━━━━━┻━━━━━━━┻━━━━━━━┹────────────────────────────────┺━━━━━━━┻━━━━━━━┻━━━━━━━┻━━━━━━━┛
;

const abnt_rows = [_]RowDescription{
    .{
        .offset = 1,
        .keys = &[_]KeyCode{ .tlde, .ae01, .ae02, .ae03, .ae04, .ae05, .ae06, .ae07, .ae08, .ae09, .ae10, .ae11, .ae12 },
    },
    .{
        .offset = 10,
        .keys = &[_]KeyCode{ .ad01, .ad02, .ad03, .ad04, .ad05, .ad06, .ad07, .ad08, .ad09, .ad10, .ad11, .ad12 },
    },
    .{
        .offset = 11,
        .keys = &[_]KeyCode{ .ac01, .ac02, .ac03, .ac04, .ac05, .ac06, .ac07, .ac08, .ac09, .ac10, .ac11, .bksl },
    },
    .{
        .offset = 8,
        .keys = &[_]KeyCode{ .lsgt, .ab01, .ab02, .ab03, .ab04, .ab05, .ab06, .ab07, .ab08, .ab09, .ab10, .ab11 },
    },
};

const jis_template =
    \\┏━━━━━┱─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┲━━━━━┓
    \\┃     ┃     │     │     │     │     │     │     │     │     │     │     │     │     ┃     ┃
    \\┃ W.  ┃     │     │     │     │     │     │     │     │     │     │     │     │     ┃ ⌫   ┃
    \\┣━━━━━┻━━┱──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┲━━┻━━━━━┫
    \\┃        ┃     │     │     │     │     │     │     │     │     │     │     │     ┃        ┃
    \\┃ ↹      ┃     │     │     │     │     │     │     │     │     │     │     │     ┃        ┃
    \\┣━━━━━━━━┻┱────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┺┓  ⏎    ┃
    \\┃         ┃     │     │     │     │     │     │     │     │     │     │     │     ┃       ┃
    \\┃ ⇬       ┃     │     │     │     │     │     │     │     │     │     │     │     ┃       ┃
    \\┣━━━━━━━━━┻━━┱──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┲━━┻━━━━━━━┫
    \\┃            ┃     │     │     │     │     │     │     │     │     │     │     ┃          ┃
    \\┃ ⇧          ┃     │     │     │     │     │     │     │     │     │     │     ┃ ⇧        ┃
    \\┣━━━━━━━┳━━━━┻━━┳━━┷━━━━┳┷━━━━┱┴─────┴─────┴─┲━━━┷━┳━━━┷━┳━━━┷━━━┳━┷━━━━━╈━━━━━┻━┳━━━━━━━━┫
    \\┃       ┃       ┃       ┃     ┃              ┃     ┃     ┃       ┃       ┃       ┃        ┃
    \\┃ Ctrl  ┃ super ┃ Alt   ┃ NC. ┃ ␣            ┃ C.  ┃ K.  ┃ Alt   ┃ super ┃ menu  ┃ Ctrl   ┃
    \\┗━━━━━━━┻━━━━━━━┻━━━━━━━┻━━━━━┹──────────────┺━━━━━┻━━━━━┻━━━━━━━┻━━━━━━━┻━━━━━━━┻━━━━━━━━┛
;

const jis_rows = [_]RowDescription{
    .{
        .offset = 7,
        .keys = &[_]KeyCode{ .ae01, .ae02, .ae03, .ae04, .ae05, .ae06, .ae07, .ae08, .ae09, .ae10, .ae11, .ae12, .ae13 },
    },
    .{
        .offset = 10,
        .keys = &[_]KeyCode{ .ad01, .ad02, .ad03, .ad04, .ad05, .ad06, .ad07, .ad08, .ad09, .ad10, .ad11, .ad12 },
    },
    .{
        .offset = 11,
        .keys = &[_]KeyCode{ .ac01, .ac02, .ac03, .ac04, .ac05, .ac06, .ac07, .ac08, .ac09, .ac10, .ac11, .bksl },
    },
    .{
        .offset = 14,
        .keys = &[_]KeyCode{ .ab01, .ab02, .ab03, .ab04, .ab05, .ab06, .ab07, .ab08, .ab09, .ab10, .ab11 },
    },
};

const alt_template =
    \\┌─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┲━━━━━┓
    \\│     │     │     │     │     │     │     │     │     │     │     │     │     │     ┃     ┃
    \\│     │     │     │     │     │     │     │     │     │     │     │     │     │     ┃ ⌫   ┃
    \\┢━━━━━┷━━┱──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┲━━┻━━━━━┫
    \\┃        ┃     │     │     │     │     │     │     │     │     │     │     │     ┃        ┃
    \\┃ ↹      ┃     │     │     │     │     │     │     │     │     │     │     │     ┃        ┃
    \\┣━━━━━━━━┻┱────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┲━━━━┛   ⏎    ┃
    \\┃         ┃     │     │     │     │     │     │     │     │     │     │     ┃             ┃
    \\┃ ⇬       ┃     │     │     │     │     │     │     │     │     │     │     ┃             ┃
    \\┣━━━━━━━━━┻━━┱──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┲━━┻━━━━━━━━━━━━━┫
    \\┃            ┃     │     │     │     │     │     │     │     │     │     ┃                ┃
    \\┃ ⇧          ┃     │     │     │     │     │     │     │     │     │     ┃ ⇧              ┃
    \\┣━━━━━━━┳━━━━┻━━┳━━┷━━━━┱┴─────┴─────┴─────┴─────┴─────┴─┲━━━┷━━━┳━┷━━━━━╋━━━━━━━┳━━━━━━━━┫
    \\┃       ┃       ┃       ┃                                ┃       ┃       ┃       ┃        ┃
    \\┃ Ctrl  ┃ super ┃ Alt   ┃ ␣                              ┃ Alt   ┃ super ┃ menu  ┃ Ctrl   ┃
    \\┗━━━━━━━┻━━━━━━━┻━━━━━━━┹────────────────────────────────┺━━━━━━━┻━━━━━━━┻━━━━━━━┻━━━━━━━━┛
;

const alt_rows = [_]RowDescription{
    .{
        .offset = 1,
        .keys = &[_]KeyCode{ .tlde, .ae01, .ae02, .ae03, .ae04, .ae05, .ae06, .ae07, .ae08, .ae09, .ae10, .ae11, .ae12, .bksl },
    },
    .{
        .offset = 10,
        .keys = &[_]KeyCode{ .ad01, .ad02, .ad03, .ad04, .ad05, .ad06, .ad07, .ad08, .ad09, .ad10, .ad11, .ad12 },
    },
    .{
        .offset = 11,
        .keys = &[_]KeyCode{ .ac01, .ac02, .ac03, .ac04, .ac05, .ac06, .ac07, .ac08, .ac09, .ac10, .ac11 },
    },
    .{
        .offset = 14,
        .keys = &[_]KeyCode{ .ab01, .ab02, .ab03, .ab04, .ab05, .ab06, .ab07, .ab08, .ab09, .ab10 },
    },
};
