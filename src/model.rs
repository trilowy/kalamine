use clap::ValueEnum;

#[derive(Debug, Clone, ValueEnum, Default)]
#[clap(rename_all = "snake_case")]
pub enum OutputType {
    #[default]
    All,
    Keylayout,
    Klc,
    XkbKeymap,
    XkbSymbols,
    Svg,
}

#[derive(Debug, Clone, ValueEnum, Default)]
#[clap(rename_all = "UPPERCASE")]
pub enum KeyboardGeometry {
    #[default]
    Iso,
    Ansi,
    Ergo,
    Abnt,
    Jis,
    Alt,
}

pub struct KeyboardLayout {
    // TODO
    name: String,
    name8: String, // TODO validation
    variant: String,
    file_name: String,
    locale: String, // TODO validation
    geometry: KeyboardGeometry,
    description: String,
    author: String,
    license: String,
    version: String,
    url: String, // TODO validation
    keys: [[Key; 4]; 6],
}

struct Key {
    // TODO
    base: Option<ShiftableChar>,
    altgr: Option<ShiftableChar>,
    odk: Option<ShiftableChar>,
}

struct ShiftableChar {
    // TODO
    unshift: Option<char>,
    shift: Option<char>,
}
