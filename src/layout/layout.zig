const std = @import("std");
const toml = @import("toml");

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

const Layer = enum {
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
    error_message: ?[]const u8 = null,
};

pub const KeyboardLayout = struct {
    // TODO: kalamine/layout.py:142

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

    /// Deinitialize with `deinit`
    /// In case of error, deinitialize the error message if present in options
    pub fn initFromToml(
        allocator: std.mem.Allocator,
        reader: *std.Io.Reader,
        options: *ParseOptions,
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

        // Own the memory of each field to free the rest
        const name = if (parsed_toml.name) |name|
            try allocator.dupe(u8, name)
        else {
            options.error_message = try allocator.dupe(u8, "Parse error: missing mandatory 'name' attribute\n");
            return error.LayoutParsingError;
        };

        const name8 = if (parsed_toml.name8) |name8|
            try allocator.dupe(u8, name8)
        else
            try allocator.dupe(u8, name[0..8]);

        const locale = if (parsed_toml.locale) |locale|
            try allocator.dupe(u8, locale)
        else
            null;

        const variant = if (parsed_toml.variant) |variant|
            try allocator.dupe(u8, variant)
        else
            null;

        const author = if (parsed_toml.author) |author|
            try allocator.dupe(u8, author)
        else
            null;

        const description = if (parsed_toml.description) |description|
            try allocator.dupe(u8, description)
        else
            null;

        const url = if (parsed_toml.url) |url|
            try allocator.dupe(u8, url)
        else
            null;

        const version = if (parsed_toml.version) |version|
            try allocator.dupe(u8, version)
        else
            null;

        const geometry = if (parsed_toml.geometry) |geometry|
            geometry
        else {
            options.error_message = try allocator.dupe(u8, "Parse error: missing mandatory 'geometry' attribute\n");
            return error.LayoutParsingError;
        };

        var layers = std.AutoHashMapUnmanaged(Layer, std.AutoHashMapUnmanaged(KeyCode, []u8)).empty;
        for (std.enums.values(Layer)) |layer| {
            try layers.put(allocator, layer, std.AutoHashMapUnmanaged(KeyCode, []u8).empty);
        }

        return KeyboardLayout{
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
    }

    pub fn deinit(self: *KeyboardLayout, allocator: std.mem.Allocator) void {
        allocator.free(self.name);

        allocator.free(self.name8);

        if (self.locale) |locale| {
            allocator.free(locale);
        }

        if (self.variant) |variant| {
            allocator.free(variant);
        }

        if (self.author) |author| {
            allocator.free(author);
        }

        if (self.description) |description| {
            allocator.free(description);
        }

        if (self.url) |url| {
            allocator.free(url);
        }

        if (self.version) |version| {
            allocator.free(version);
        }

        var layers_iterator = self.layers.valueIterator();
        while (layers_iterator.next()) |layer| {
            layer.deinit(allocator);
        }
        self.layers.deinit(allocator);

        self.* = undefined;
    }

    /// Extract a keyboard layer from a template
    fn parseTemplate(
        allocator: std.mem.Allocator,
        template: []const []const u8,
        rows: []const RowDescription,
        layer: Layer,
    ) !void {
        var j = 0;
        const col_offset = if (layer == .base) 0 else 2;
        for (rows) |row| {
            var i = row.offset + col_offset;

            const base = template[2 + j * 3];
            const shift = template[1 + j * 3];

            for (row.keys) |key| {
                var base_key = if (base[i - 1] == '*') {
                    return base[(i - 1)..(i + 1)];
                } else {
                    return base[i..(i + 1)];
                };

                const shift_key = if (base[i - 1] == '*') {
                    return shift[(i - 1)..(i + 1)];
                } else {
                    return shift[i..(i + 1)];
                };

                // In the base layer, if the base character is undefined, shift prevails
                if (std.mem.eql(u8, base_key, " ")) {
                    if (layer == .base) {
                        // TODO: alloc all keys to keep them, need to free the previous base_key
                        // Or, I can use enum for all possible values? Is it useful for driver generation?
                        base_key = try std.ascii.allocLowerString(allocator, shift_key);
                        // TODO: kalamine/layout.py:295
                        _ = key; // TODO:
                    }
                }

                i += 6;
            }
            j += 1;
        }
    }
};

// TODO: kalamine/layout.py:276
// parse template the same as python version? how to make it more robust?
// better parsing error message?
// parse first the template to see if it matches perfectly first?
// tips of why it might not match: spaces at the beginning of the line
// row and column where it does not match

const RowDescription = struct {
    offset: usize,
    keys: []const KeyCode,
};

const KeyCode = enum {
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
    \\
;

const iso_rows = [_]RowDescription{
    .{
        .offset = 2,
        .keys = &[_]KeyCode{ .tlde, .ae01, .ae02, .ae03, .ae04, .ae05, .ae06, .ae07, .ae08, .ae09, .ae10, .ae11, .ae12 },
    },
    .{
        .offset = 11,
        .keys = &[_]KeyCode{ .ad01, .ad02, .ad03, .ad04, .ad05, .ad06, .ad07, .ad08, .ad09, .ad10, .ad11, .ad12 },
    },
    .{
        .offset = 12,
        .keys = &[_]KeyCode{ .ac01, .ac02, .ac03, .ac04, .ac05, .ac06, .ac07, .ac08, .ac09, .ac10, .ac11, .bksl },
    },
    .{
        .offset = 9,
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
    \\
;

const ansi_rows = [_]RowDescription{
    .{
        .offset = 2,
        .keys = &[_]KeyCode{ .tlde, .ae01, .ae02, .ae03, .ae04, .ae05, .ae06, .ae07, .ae08, .ae09, .ae10, .ae11, .ae12 },
    },
    .{
        .offset = 11,
        .keys = &[_]KeyCode{ .ad01, .ad02, .ad03, .ad04, .ad05, .ad06, .ad07, .ad08, .ad09, .ad10, .ad11, .ad12, .bksl },
    },
    .{
        .offset = 12,
        .keys = &[_]KeyCode{ .ac01, .ac02, .ac03, .ac04, .ac05, .ac06, .ac07, .ac08, .ac09, .ac10, .ac11 },
    },
    .{
        .offset = 15,
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
    \\
;

const ergo_rows = [_]RowDescription{
    .{
        .offset = 2,
        .keys = &[_]KeyCode{ .tlde, .ae01, .ae02, .ae03, .ae04, .ae05, .ae06, .ae07, .ae08, .ae09, .ae10, .ae11, .ae12 },
    },
    .{
        .offset = 8,
        .keys = &[_]KeyCode{ .ad01, .ad02, .ad03, .ad04, .ad05, .ad06, .ad07, .ad08, .ad09, .ad10, .ad11, .ad12 },
    },
    .{
        .offset = 8,
        .keys = &[_]KeyCode{ .ac01, .ac02, .ac03, .ac04, .ac05, .ac06, .ac07, .ac08, .ac09, .ac10, .ac11, .bksl },
    },
    .{
        .offset = 2,
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
    \\
;

const abnt_rows = [_]RowDescription{
    .{
        .offset = 2,
        .keys = &[_]KeyCode{ .tlde, .ae01, .ae02, .ae03, .ae04, .ae05, .ae06, .ae07, .ae08, .ae09, .ae10, .ae11, .ae12 },
    },
    .{
        .offset = 11,
        .keys = &[_]KeyCode{ .ad01, .ad02, .ad03, .ad04, .ad05, .ad06, .ad07, .ad08, .ad09, .ad10, .ad11, .ad12 },
    },
    .{
        .offset = 12,
        .keys = &[_]KeyCode{ .ac01, .ac02, .ac03, .ac04, .ac05, .ac06, .ac07, .ac08, .ac09, .ac10, .ac11, .bksl },
    },
    .{
        .offset = 9,
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
    \\
;

const jis_rows = [_]RowDescription{
    .{
        .offset = 8,
        .keys = &[_]KeyCode{ .ae01, .ae02, .ae03, .ae04, .ae05, .ae06, .ae07, .ae08, .ae09, .ae10, .ae11, .ae12, .ae13 },
    },
    .{
        .offset = 11,
        .keys = &[_]KeyCode{ .ad01, .ad02, .ad03, .ad04, .ad05, .ad06, .ad07, .ad08, .ad09, .ad10, .ad11, .ad12 },
    },
    .{
        .offset = 12,
        .keys = &[_]KeyCode{ .ac01, .ac02, .ac03, .ac04, .ac05, .ac06, .ac07, .ac08, .ac09, .ac10, .ac11, .bksl },
    },
    .{
        .offset = 15,
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
    \\
;

const alt_rows = [_]RowDescription{
    .{
        .offset = 2,
        .keys = &[_]KeyCode{ .tlde, .ae01, .ae02, .ae03, .ae04, .ae05, .ae06, .ae07, .ae08, .ae09, .ae10, .ae11, .ae12, .bksl },
    },
    .{
        .offset = 11,
        .keys = &[_]KeyCode{ .ad01, .ad02, .ad03, .ad04, .ad05, .ad06, .ad07, .ad08, .ad09, .ad10, .ad11, .ad12 },
    },
    .{
        .offset = 12,
        .keys = &[_]KeyCode{ .ac01, .ac02, .ac03, .ac04, .ac05, .ac06, .ac07, .ac08, .ac09, .ac10, .ac11 },
    },
    .{
        .offset = 15,
        .keys = &[_]KeyCode{ .ab01, .ab02, .ab03, .ab04, .ab05, .ab06, .ab07, .ab08, .ab09, .ab10 },
    },
};
