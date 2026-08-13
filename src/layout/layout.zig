const std = @import("std");
const toml = @import("toml");
const layout_parser = @import("parser.zig");
const ParsedKey = layout_parser.ParsedKey;
const LetterCasing = @import("LetterCasing");
const Graphemes = @import("Graphemes");
const error_handling = @import("../error_handling.zig");
const ParseOptions = error_handling.ParseOptions;
const ParsingError = error_handling.ParsingError;

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

        // TODO: line of the TOML is better for the feedback in diagnostic
        if (parsed_toml.full) |full_to_parse| {
            if (options.diagnostic) |diag| diag.arg = "full";

            var keymap = try layout_parser.parseLayout(allocator, keyboard_layout.geometry, full_to_parse, options);
            defer keymap.deinit(allocator);

            // TODO: loop on multiple layers at the same time?
            try keyboard_layout.parseTemplate(allocator, &keymap, Layer.base, options);
            try keyboard_layout.parseTemplate(allocator, &keymap, Layer.altgr, options);

            keyboard_layout.has_altgr = true;

            if (options.diagnostic) |diag| diag.arg = "";
        } else if (parsed_toml.base) |base_to_parse| {
            if (options.diagnostic) |diag| diag.arg = "base";

            // FIXME: commented to test error handling
            _ = base_to_parse;
            // var keymap = try layout_parser.parseLayout(allocator, keyboard_layout.geometry, base_to_parse, options);
            // defer keymap.deinit(allocator);

            // try keyboard_layout.parseTemplate(allocator, &keymap, Layer.base, options);
            // try keyboard_layout.parseTemplate(allocator, &keymap, Layer.odk, options);

            if (parsed_toml.altgr) |altgr_to_parse| {
                if (options.diagnostic) |diag| diag.arg = "altgr";

                var altgr_keymap = try layout_parser.parseLayout(allocator, keyboard_layout.geometry, altgr_to_parse, options);
                defer altgr_keymap.deinit(allocator);

                try keyboard_layout.parseTemplate(allocator, &altgr_keymap, Layer.altgr, options);

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
        keymap: *const std.AutoHashMapUnmanaged(KeyCode, ParsedKey),
        layer: Layer,
        options: ParseOptions,
    ) !void {
        const arena = self.arena_allocator.allocator();

        const case = try LetterCasing.init(allocator);
        defer case.deinit(allocator);

        var layer_map = self.layers.getPtr(layer).?;
        var layer_map_shift = self.layers.getPtr(layer.shifted()).?;

        var keymap_iter = keymap.iterator();

        while (keymap_iter.next()) |entry| {
            const key_code = entry.key_ptr.*;
            const parsed_key = entry.value_ptr.*;

            if (layer == .base) {
                if (parsed_key.left_up) |shift_key| {
                    const key_to_put_shift = try arena.dupe(u8, shift_key);
                    try layer_map_shift.put(arena, key_code, key_to_put_shift);

                    // In the base layer, if the base character is undefined, shift prevails
                    if (parsed_key.left_down == null) {
                        const key_to_put_base = try case.toLowerStr(arena, key_to_put_shift);
                        try layer_map.put(arena, key_code, key_to_put_base);
                    }
                }

                if (parsed_key.left_down) |base_key| {
                    const key_to_put_base = try arena.dupe(u8, base_key);
                    try layer_map.put(arena, key_code, key_to_put_base);
                }
            } else if (layer == .altgr or layer == .odk) {
                if (parsed_key.right_down) |base_key| {
                    const key_to_put_base = try arena.dupe(u8, base_key);
                    try layer_map.put(arena, key_code, key_to_put_base);

                    // In other layers, if the shift character is undefined, base prevails
                    if (parsed_key.right_up == null) {
                        const key_to_put_shift = try case.toUpperStr(arena, key_to_put_base);
                        try layer_map_shift.put(arena, key_code, key_to_put_shift);
                    }
                }

                if (parsed_key.right_up) |shift_key| {
                    const key_to_put_shift = try arena.dupe(u8, shift_key);
                    try layer_map_shift.put(arena, key_code, key_to_put_shift);
                }
            }
        }

        // TODO: kalamine/layout.py:311
        // dead_keys set
        _ = options;
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
