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

    base_layer: Layer,
    shif_base_layer: Option<Layer>,
    altgr_layer: Option<Layer>,
    shift_altgr_layer: Option<Layer>,
    odk_layer: Option<Layer>,
    shift_odk_layer: Option<Layer>,
}

type Character = char;

struct Layer {
    keys: Vec<Vec<Option<Character>>>,
}
