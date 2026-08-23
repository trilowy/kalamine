const KeyCode = @import("../layout.zig").KeyCode;

pub fn scancode(key_code: KeyCode) []const u8 {
    return switch (key_code) {
        // Digits
        .ae01 => "02",
        .ae02 => "03",
        .ae03 => "04",
        .ae04 => "05",
        .ae05 => "06",
        .ae06 => "07",
        .ae07 => "08",
        .ae08 => "09",
        .ae09 => "0a",
        .ae10 => "0b",
        // Letters, first row
        .ad01 => "10",
        .ad02 => "11",
        .ad03 => "12",
        .ad04 => "13",
        .ad05 => "14",
        .ad06 => "15",
        .ad07 => "16",
        .ad08 => "17",
        .ad09 => "18",
        .ad10 => "19",
        // Letters, second row
        .ac01 => "1e",
        .ac02 => "1f",
        .ac03 => "20",
        .ac04 => "21",
        .ac05 => "22",
        .ac06 => "23",
        .ac07 => "24",
        .ac08 => "25",
        .ac09 => "26",
        .ac10 => "27",
        // Letters, third row
        .ab01 => "2c",
        .ab02 => "2d",
        .ab03 => "2e",
        .ab04 => "2f",
        .ab05 => "30",
        .ab06 => "31",
        .ab07 => "32",
        .ab08 => "33",
        .ab09 => "34",
        .ab10 => "35",
        // Pinky keys
        .ae11 => "0c",
        .ae12 => "0d",
        .ae13 => "0d", // FIXME:
        .ad11 => "1a",
        .ad12 => "1b",
        .ac11 => "28",
        .ab11 => "28", // FIXME:
        .tlde => "29",
        .bksl => "2b",
        .lsgt => "56",
        // Space bar
        .spce => "39",
    };
}
