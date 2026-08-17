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

pub const Layer = enum {
    base,
    shift,
    odk,
    odk_shift,
    altgr,
    altgr_shift,

    pub fn shifted(self: Layer) Layer {
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

pub const KeyboardLayout = struct {
    // TODO: kalamine/layout.py:142

    /// Store all values, used for deinit
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
    /// Base layer is mandatory
    /// Altgr and 1dk layers are optional
    /// A layer has always its shifted layer
    /// If a layer has an non-shifted character, its shifted layer will always contains the
    /// shifted version and vice-versa
    layers: std.AutoHashMapUnmanaged(Layer, std.AutoHashMapUnmanaged(KeyCode, []const u8)),

    pub fn deinit(self: *KeyboardLayout) void {
        self.arena_allocator.deinit();
        self.* = undefined;
    }

    pub fn hasAltgr(self: *const KeyboardLayout) bool {
        return self.layers.contains(.altgr);
    }

    pub fn hasOdk(self: *const KeyboardLayout) bool {
        return self.layers.contains(.odk);
    }
};

// TODO: kalamine/layout.py:276

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
    spce,
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
