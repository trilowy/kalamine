const std = @import("std");

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

pub const KeyboardLayout = struct {
    // TODO: kalamine/layout.py:142
    name: ?[]const u8,
    name8: []const u8,
    locale: ?[]const u8,
    variant: ?[]const u8,
    description: ?[]const u8,
    author: ?[]const u8,
    url: ?[]const u8,
    geometry: Geometry,
    version: ?[]const u8,

    /// Extract a keyboard layer from a template
    fn parseTemplate(
        self: *KeyboardLayout,
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
