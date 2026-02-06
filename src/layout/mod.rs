use clap::ValueEnum;
use std::collections::HashMap;

#[derive(Debug, Clone, ValueEnum, Default)]
#[clap(rename_all = "UPPERCASE")]
pub enum Geometry {
    #[default]
    Iso,
    Ansi,
    Ergo,
    Abnt,
    Jis,
    Alt,
}

impl Geometry {
    fn get_template(self) -> &'static str {
        match self {
            Self::Iso => ISO_TEMPLATE,
            Self::Ansi => ANSI_TEMPLATE,
            Self::Ergo => ERGO_TEMPLATE,
            Self::Abnt => ABNT_TEMPLATE,
            Self::Jis => JIS_TEMPLATE,
            Self::Alt => ALT_TEMPLATE,
        }
    }

    fn get_keys(self) -> [RowDescription<'static>; 4] {
        match self {
            Self::Iso => ISO_ROWS,
            Self::Ansi => ANSI_ROWS,
            Self::Ergo => ERGO_ROWS,
            Self::Abnt => ABNT_ROWS,
            Self::Jis => JIS_ROWS,
            Self::Alt => ALT_ROWS,
        }
    }
}

pub enum Layer {
    Base,
    Shift,
    Odk,
    OdkShift,
    Altgr,
    AltgrShift,
}

impl Layer {
    fn shifted(self) -> Layer {
        return match self {
            Self::Base => Self::Shift,
            Self::Shift => Self::Shift,
            Self::Odk => Self::OdkShift,
            Self::OdkShift => Self::OdkShift,
            Self::Altgr => Self::AltgrShift,
            Self::AltgrShift => Self::AltgrShift,
        };
    }
}

pub struct KeyboardLayout {
    // TODO:
    /// Full layout name, displayed in the keyboard settings
    name: String,
    /// Short Windows filename: no spaces, no special chars
    name8: String, // TODO: validation
    /// Locale/language ID
    locale: Option<String>, // TODO: validation
    /// Layout variant ID
    variant: Option<String>,
    /// Author name
    author: Option<String>,
    description: Option<String>,
    url: Option<String>, // TODO: validation
    version: Option<String>,
    geometry: Geometry,
    layers: HashMap<Layer, HashMap<KeyCode, String>>,
    has_altgr: bool,
    has_1dk: bool,

    // FIXME: see if better than hashmap
    base_layer: Layer,
    shift_base_layer: Option<Layer>,
    altgr_layer: Option<Layer>,
    shift_altgr_layer: Option<Layer>,
    odk_layer: Option<Layer>,
    shift_odk_layer: Option<Layer>,
}

// TODO: kalamine/layout.py:276
// parse template the same as python version? how to make it more robust?
// better parsing error message?
// parse first the template to see if it matches perfectly first?
// tips of why it might not match: spaces at the beginning of the line
// row and column where it does not match

pub struct RowDescription<'a> {
    offset: usize,
    keys: &'a [KeyCode],
}

pub enum KeyCode {
    Ab01,
    Ab02,
    Ab03,
    Ab04,
    Ab05,
    Ab06,
    Ab07,
    Ab08,
    Ab09,
    Ab10,
    Ab11,
    Ac01,
    Ac02,
    Ac03,
    Ac04,
    Ac05,
    Ac06,
    Ac07,
    Ac08,
    Ac09,
    Ac10,
    Ac11,
    Ad01,
    Ad02,
    Ad03,
    Ad04,
    Ad05,
    Ad06,
    Ad07,
    Ad08,
    Ad09,
    Ad10,
    Ad11,
    Ad12,
    Ae01,
    Ae02,
    Ae03,
    Ae04,
    Ae05,
    Ae06,
    Ae07,
    Ae08,
    Ae09,
    Ae10,
    Ae11,
    Ae12,
    Ae13,
    Bksl,
    Lsgt,
    Tlde,
}

const ISO_TEMPLATE: &str = r#"
┌─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┲━━━━━━━━━━┓
│     │     │     │     │     │     │     │     │     │     │     │     │     ┃          ┃
│     │     │     │     │     │     │     │     │     │     │     │     │     ┃ ⌫        ┃
┢━━━━━┷━━┱──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┺━━┳━━━━━━━┫
┃        ┃     │     │     │     │     │     │     │     │     │     │     │     ┃       ┃
┃ ↹      ┃     │     │     │     │     │     │     │     │     │     │     │     ┃       ┃
┣━━━━━━━━┻┱────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┺┓  ⏎   ┃
┃         ┃     │     │     │     │     │     │     │     │     │     │     │     ┃      ┃
┃ ⇬       ┃     │     │     │     │     │     │     │     │     │     │     │     ┃      ┃
┣━━━━━━┳━━┹──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┲━━┷━━━━━┻━━━━━━┫
┃      ┃     │     │     │     │     │     │     │     │     │     │     ┃               ┃
┃ ⇧    ┃     │     │     │     │     │     │     │     │     │     │     ┃ ⇧             ┃
┣━━━━━━┻┳━━━━┷━━┳━━┷━━━━┱┴─────┴─────┴─────┴─────┴─────┴─┲━━━┷━━━┳━┷━━━━━╋━━━━━━━┳━━━━━━━┫
┃       ┃       ┃       ┃                                ┃       ┃       ┃       ┃       ┃
┃ Ctrl  ┃ super ┃ Alt   ┃ ␣                              ┃ AltGr ┃ super ┃ menu  ┃ Ctrl  ┃
┗━━━━━━━┻━━━━━━━┻━━━━━━━┹────────────────────────────────┺━━━━━━━┻━━━━━━━┻━━━━━━━┻━━━━━━━┛
"#;

const ISO_ROWS: [RowDescription; 4] = [
    RowDescription {
        offset: 1,
        keys: &[
            KeyCode::Tlde,
            KeyCode::Ae01,
            KeyCode::Ae02,
            KeyCode::Ae03,
            KeyCode::Ae04,
            KeyCode::Ae05,
            KeyCode::Ae06,
            KeyCode::Ae07,
            KeyCode::Ae08,
            KeyCode::Ae09,
            KeyCode::Ae10,
            KeyCode::Ae11,
            KeyCode::Ae12,
        ],
    },
    RowDescription {
        offset: 10,
        keys: &[
            KeyCode::Ad01,
            KeyCode::Ad02,
            KeyCode::Ad03,
            KeyCode::Ad04,
            KeyCode::Ad05,
            KeyCode::Ad06,
            KeyCode::Ad07,
            KeyCode::Ad08,
            KeyCode::Ad09,
            KeyCode::Ad10,
            KeyCode::Ad11,
            KeyCode::Ad12,
        ],
    },
    RowDescription {
        offset: 11,
        keys: &[
            KeyCode::Ac01,
            KeyCode::Ac02,
            KeyCode::Ac03,
            KeyCode::Ac04,
            KeyCode::Ac05,
            KeyCode::Ac06,
            KeyCode::Ac07,
            KeyCode::Ac08,
            KeyCode::Ac09,
            KeyCode::Ac10,
            KeyCode::Ac11,
            KeyCode::Bksl,
        ],
    },
    RowDescription {
        offset: 8,
        keys: &[
            KeyCode::Lsgt,
            KeyCode::Ab01,
            KeyCode::Ab02,
            KeyCode::Ab03,
            KeyCode::Ab04,
            KeyCode::Ab05,
            KeyCode::Ab06,
            KeyCode::Ab07,
            KeyCode::Ab08,
            KeyCode::Ab09,
            KeyCode::Ab10,
        ],
    },
];

const ANSI_TEMPLATE: &str = r#"
┌─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┲━━━━━━━━━━┓
│     │     │     │     │     │     │     │     │     │     │     │     │     ┃          ┃
│     │     │     │     │     │     │     │     │     │     │     │     │     ┃ ⌫        ┃
┢━━━━━┷━━┱──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┺━━┯━━━━━━━┩
┃        ┃     │     │     │     │     │     │     │     │     │     │     │     │       │
┃ ↹      ┃     │     │     │     │     │     │     │     │     │     │     │     │       │
┣━━━━━━━━┻┱────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┲━━━━┷━━━━━━━┪
┃         ┃     │     │     │     │     │     │     │     │     │     │     ┃            ┃
┃ ⇬       ┃     │     │     │     │     │     │     │     │     │     │     ┃ ⏎          ┃
┣━━━━━━━━━┻━━┱──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┲━━┻━━━━━━━━━━━━┫
┃            ┃     │     │     │     │     │     │     │     │     │     ┃               ┃
┃ ⇧          ┃     │     │     │     │     │     │     │     │     │     ┃ ⇧             ┃
┣━━━━━━━┳━━━━┻━━┳━━┷━━━━┱┴─────┴─────┴─────┴─────┴─────┴─┲━━━┷━━━┳━┷━━━━━╋━━━━━━━┳━━━━━━━┫
┃       ┃       ┃       ┃                                ┃       ┃       ┃       ┃       ┃
┃ Ctrl  ┃ super ┃ Alt   ┃ ␣                              ┃ Alt   ┃ super ┃ menu  ┃ Ctrl  ┃
┗━━━━━━━┻━━━━━━━┻━━━━━━━┹────────────────────────────────┺━━━━━━━┻━━━━━━━┻━━━━━━━┻━━━━━━━┛
"#;

const ANSI_ROWS: [RowDescription; 4] = [
    RowDescription {
        offset: 1,
        keys: &[
            KeyCode::Tlde,
            KeyCode::Ae01,
            KeyCode::Ae02,
            KeyCode::Ae03,
            KeyCode::Ae04,
            KeyCode::Ae05,
            KeyCode::Ae06,
            KeyCode::Ae07,
            KeyCode::Ae08,
            KeyCode::Ae09,
            KeyCode::Ae10,
            KeyCode::Ae11,
            KeyCode::Ae12,
        ],
    },
    RowDescription {
        offset: 10,
        keys: &[
            KeyCode::Ad01,
            KeyCode::Ad02,
            KeyCode::Ad03,
            KeyCode::Ad04,
            KeyCode::Ad05,
            KeyCode::Ad06,
            KeyCode::Ad07,
            KeyCode::Ad08,
            KeyCode::Ad09,
            KeyCode::Ad10,
            KeyCode::Ad11,
            KeyCode::Ad12,
            KeyCode::Bksl,
        ],
    },
    RowDescription {
        offset: 11,
        keys: &[
            KeyCode::Ac01,
            KeyCode::Ac02,
            KeyCode::Ac03,
            KeyCode::Ac04,
            KeyCode::Ac05,
            KeyCode::Ac06,
            KeyCode::Ac07,
            KeyCode::Ac08,
            KeyCode::Ac09,
            KeyCode::Ac10,
            KeyCode::Ac11,
        ],
    },
    RowDescription {
        offset: 14,
        keys: &[
            KeyCode::Ab01,
            KeyCode::Ab02,
            KeyCode::Ab03,
            KeyCode::Ab04,
            KeyCode::Ab05,
            KeyCode::Ab06,
            KeyCode::Ab07,
            KeyCode::Ab08,
            KeyCode::Ab09,
            KeyCode::Ab10,
        ],
    },
];

const ERGO_TEMPLATE: &str = r#"
╭╌╌╌╌╌┰─────┬─────┬─────┬─────┬─────┰─────┬─────┬─────┬─────┬─────┰╌╌╌╌╌┬╌╌╌╌╌╮
┆     ┃     │     │     │     │     ┃     │     │     │     │     ┃     ┆     ┆
┆     ┃     │     │     │     │     ┃     │     │     │     │     ┃     ┆     ┆
╰╌╌╌╌╌╂─────┼─────┼─────┼─────┼─────╂─────┼─────┼─────┼─────┼─────╂╌╌╌╌╌┼╌╌╌╌╌┤
      ┃     │     │     │     │     ┃     │     │     │     │     ┃     ┆     ┆
      ┃     │     │     │     │     ┃     │     │     │     │     ┃     ┆     ┆
      ┠─────┼─────┼─────┼─────┼─────╂─────┼─────┼─────┼─────┼─────╂╌╌╌╌╌┼╌╌╌╌╌┤
      ┃     │     │     │     │     ┃     │     │     │     │     ┃     ┆     ┆
      ┃     │     │     │     │     ┃     │     │     │     │     ┃     ┆     ┆
╭╌╌╌╌╌╂─────┼─────┼─────┼─────┼─────╂─────┼─────┼─────┼─────┼─────╂╌╌╌╌╌┴╌╌╌╌╌╯
┆     ┃     │     │     │     │     ┃     │     │     │     │     ┃
┆     ┃     │     │     │     │     ┃     │     │     │     │     ┃
╰╌╌╌╌╌┸─────┴─────┴─────┴─────┴─────┸─────┴─────┴─────┴─────┴─────┚
"#;

const ERGO_ROWS: [RowDescription; 4] = [
    RowDescription {
        offset: 1,
        keys: &[
            KeyCode::Tlde,
            KeyCode::Ae01,
            KeyCode::Ae02,
            KeyCode::Ae03,
            KeyCode::Ae04,
            KeyCode::Ae05,
            KeyCode::Ae06,
            KeyCode::Ae07,
            KeyCode::Ae08,
            KeyCode::Ae09,
            KeyCode::Ae10,
            KeyCode::Ae11,
            KeyCode::Ae12,
        ],
    },
    RowDescription {
        offset: 7,
        keys: &[
            KeyCode::Ad01,
            KeyCode::Ad02,
            KeyCode::Ad03,
            KeyCode::Ad04,
            KeyCode::Ad05,
            KeyCode::Ad06,
            KeyCode::Ad07,
            KeyCode::Ad08,
            KeyCode::Ad09,
            KeyCode::Ad10,
            KeyCode::Ad11,
            KeyCode::Ad12,
        ],
    },
    RowDescription {
        offset: 7,
        keys: &[
            KeyCode::Ac01,
            KeyCode::Ac02,
            KeyCode::Ac03,
            KeyCode::Ac04,
            KeyCode::Ac05,
            KeyCode::Ac06,
            KeyCode::Ac07,
            KeyCode::Ac08,
            KeyCode::Ac09,
            KeyCode::Ac10,
            KeyCode::Ac11,
            KeyCode::Bksl,
        ],
    },
    RowDescription {
        offset: 1,
        keys: &[
            KeyCode::Lsgt,
            KeyCode::Ab01,
            KeyCode::Ab02,
            KeyCode::Ab03,
            KeyCode::Ab04,
            KeyCode::Ab05,
            KeyCode::Ab06,
            KeyCode::Ab07,
            KeyCode::Ab08,
            KeyCode::Ab09,
            KeyCode::Ab10,
        ],
    },
];

const ABNT_TEMPLATE: &str = r#"
┌─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┲━━━━━━━━━━┓
│     │     │     │     │     │     │     │     │     │     │     │     │     ┃          ┃
│     │     │     │     │     │     │     │     │     │     │     │     │     ┃ ⌫        ┃
┢━━━━━┷━━┱──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┺━━┳━━━━━━━┫
┃        ┃     │     │     │     │     │     │     │     │     │     │     │     ┃       ┃
┃ ↹      ┃     │     │     │     │     │     │     │     │     │     │     │     ┃       ┃
┣━━━━━━━━┻┱────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┺┓  ⏎   ┃
┃         ┃     │     │     │     │     │     │     │     │     │     │     │     ┃      ┃
┃ ⇬       ┃     │     │     │     │     │     │     │     │     │     │     │     ┃      ┃
┣━━━━━━┳━━┹──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┲━━┻━━━━━━┫
┃      ┃     │     │     │     │     │     │     │     │     │     │     │     ┃         ┃
┃ ⇧    ┃     │     │     │     │     │     │     │     │     │     │     │     ┃ ⇧       ┃
┣━━━━━━┻┳━━━━┷━━┳━━┷━━━━┱┴─────┴─────┴─────┴─────┴─────┴─┲━━━┷━━━┳━┷━━━━━╈━━━━━┻━┳━━━━━━━┫
┃       ┃       ┃       ┃                                ┃       ┃       ┃       ┃       ┃
┃ Ctrl  ┃ super ┃ Alt   ┃ ␣                              ┃ AltGr ┃ super ┃ menu  ┃ Ctrl  ┃
┗━━━━━━━┻━━━━━━━┻━━━━━━━┹────────────────────────────────┺━━━━━━━┻━━━━━━━┻━━━━━━━┻━━━━━━━┛
"#;

const ABNT_ROWS: [RowDescription; 4] = [
    RowDescription {
        offset: 1,
        keys: &[
            KeyCode::Tlde,
            KeyCode::Ae01,
            KeyCode::Ae02,
            KeyCode::Ae03,
            KeyCode::Ae04,
            KeyCode::Ae05,
            KeyCode::Ae06,
            KeyCode::Ae07,
            KeyCode::Ae08,
            KeyCode::Ae09,
            KeyCode::Ae10,
            KeyCode::Ae11,
            KeyCode::Ae12,
        ],
    },
    RowDescription {
        offset: 10,
        keys: &[
            KeyCode::Ad01,
            KeyCode::Ad02,
            KeyCode::Ad03,
            KeyCode::Ad04,
            KeyCode::Ad05,
            KeyCode::Ad06,
            KeyCode::Ad07,
            KeyCode::Ad08,
            KeyCode::Ad09,
            KeyCode::Ad10,
            KeyCode::Ad11,
            KeyCode::Ad12,
        ],
    },
    RowDescription {
        offset: 11,
        keys: &[
            KeyCode::Ac01,
            KeyCode::Ac02,
            KeyCode::Ac03,
            KeyCode::Ac04,
            KeyCode::Ac05,
            KeyCode::Ac06,
            KeyCode::Ac07,
            KeyCode::Ac08,
            KeyCode::Ac09,
            KeyCode::Ac10,
            KeyCode::Ac11,
            KeyCode::Bksl,
        ],
    },
    RowDescription {
        offset: 8,
        keys: &[
            KeyCode::Lsgt,
            KeyCode::Ab01,
            KeyCode::Ab02,
            KeyCode::Ab03,
            KeyCode::Ab04,
            KeyCode::Ab05,
            KeyCode::Ab06,
            KeyCode::Ab07,
            KeyCode::Ab08,
            KeyCode::Ab09,
            KeyCode::Ab10,
            KeyCode::Ab11,
        ],
    },
];

const JIS_TEMPLATE: &str = r#"
┏━━━━━┱─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┲━━━━━┓
┃     ┃     │     │     │     │     │     │     │     │     │     │     │     │     ┃     ┃
┃ W.  ┃     │     │     │     │     │     │     │     │     │     │     │     │     ┃ ⌫   ┃
┣━━━━━┻━━┱──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┲━━┻━━━━━┫
┃        ┃     │     │     │     │     │     │     │     │     │     │     │     ┃        ┃
┃ ↹      ┃     │     │     │     │     │     │     │     │     │     │     │     ┃        ┃
┣━━━━━━━━┻┱────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┺┓  ⏎    ┃
┃         ┃     │     │     │     │     │     │     │     │     │     │     │     ┃       ┃
┃ ⇬       ┃     │     │     │     │     │     │     │     │     │     │     │     ┃       ┃
┣━━━━━━━━━┻━━┱──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┲━━┻━━━━━━━┫
┃            ┃     │     │     │     │     │     │     │     │     │     │     ┃          ┃
┃ ⇧          ┃     │     │     │     │     │     │     │     │     │     │     ┃ ⇧        ┃
┣━━━━━━━┳━━━━┻━━┳━━┷━━━━┳┷━━━━┱┴─────┴─────┴─┲━━━┷━┳━━━┷━┳━━━┷━━━┳━┷━━━━━╈━━━━━┻━┳━━━━━━━━┫
┃       ┃       ┃       ┃     ┃              ┃     ┃     ┃       ┃       ┃       ┃        ┃
┃ Ctrl  ┃ super ┃ Alt   ┃ NC. ┃ ␣            ┃ C.  ┃ K.  ┃ Alt   ┃ super ┃ menu  ┃ Ctrl   ┃
┗━━━━━━━┻━━━━━━━┻━━━━━━━┻━━━━━┹──────────────┺━━━━━┻━━━━━┻━━━━━━━┻━━━━━━━┻━━━━━━━┻━━━━━━━━┛
"#;

const JIS_ROWS: [RowDescription; 4] = [
    RowDescription {
        offset: 7,
        keys: &[
            KeyCode::Ae01,
            KeyCode::Ae02,
            KeyCode::Ae03,
            KeyCode::Ae04,
            KeyCode::Ae05,
            KeyCode::Ae06,
            KeyCode::Ae07,
            KeyCode::Ae08,
            KeyCode::Ae09,
            KeyCode::Ae10,
            KeyCode::Ae11,
            KeyCode::Ae12,
            KeyCode::Ae13,
        ],
    },
    RowDescription {
        offset: 10,
        keys: &[
            KeyCode::Ad01,
            KeyCode::Ad02,
            KeyCode::Ad03,
            KeyCode::Ad04,
            KeyCode::Ad05,
            KeyCode::Ad06,
            KeyCode::Ad07,
            KeyCode::Ad08,
            KeyCode::Ad09,
            KeyCode::Ad10,
            KeyCode::Ad11,
            KeyCode::Ad12,
        ],
    },
    RowDescription {
        offset: 11,
        keys: &[
            KeyCode::Ac01,
            KeyCode::Ac02,
            KeyCode::Ac03,
            KeyCode::Ac04,
            KeyCode::Ac05,
            KeyCode::Ac06,
            KeyCode::Ac07,
            KeyCode::Ac08,
            KeyCode::Ac09,
            KeyCode::Ac10,
            KeyCode::Ac11,
            KeyCode::Bksl,
        ],
    },
    RowDescription {
        offset: 14,
        keys: &[
            KeyCode::Ab01,
            KeyCode::Ab02,
            KeyCode::Ab03,
            KeyCode::Ab04,
            KeyCode::Ab05,
            KeyCode::Ab06,
            KeyCode::Ab07,
            KeyCode::Ab08,
            KeyCode::Ab09,
            KeyCode::Ab10,
            KeyCode::Ab11,
        ],
    },
];

const ALT_TEMPLATE: &str = r#"
┌─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┲━━━━━┓
│     │     │     │     │     │     │     │     │     │     │     │     │     │     ┃     ┃
│     │     │     │     │     │     │     │     │     │     │     │     │     │     ┃ ⌫   ┃
┢━━━━━┷━━┱──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┲━━┻━━━━━┫
┃        ┃     │     │     │     │     │     │     │     │     │     │     │     ┃        ┃
┃ ↹      ┃     │     │     │     │     │     │     │     │     │     │     │     ┃        ┃
┣━━━━━━━━┻┱────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┲━━━━┛   ⏎    ┃
┃         ┃     │     │     │     │     │     │     │     │     │     │     ┃             ┃
┃ ⇬       ┃     │     │     │     │     │     │     │     │     │     │     ┃             ┃
┣━━━━━━━━━┻━━┱──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┲━━┻━━━━━━━━━━━━━┫
┃            ┃     │     │     │     │     │     │     │     │     │     ┃                ┃
┃ ⇧          ┃     │     │     │     │     │     │     │     │     │     ┃ ⇧              ┃
┣━━━━━━━┳━━━━┻━━┳━━┷━━━━┱┴─────┴─────┴─────┴─────┴─────┴─┲━━━┷━━━┳━┷━━━━━╋━━━━━━━┳━━━━━━━━┫
┃       ┃       ┃       ┃                                ┃       ┃       ┃       ┃        ┃
┃ Ctrl  ┃ super ┃ Alt   ┃ ␣                              ┃ Alt   ┃ super ┃ menu  ┃ Ctrl   ┃
┗━━━━━━━┻━━━━━━━┻━━━━━━━┹────────────────────────────────┺━━━━━━━┻━━━━━━━┻━━━━━━━┻━━━━━━━━┛
"#;

const ALT_ROWS: [RowDescription; 4] = [
    RowDescription {
        offset: 1,
        keys: &[
            KeyCode::Tlde,
            KeyCode::Ae01,
            KeyCode::Ae02,
            KeyCode::Ae03,
            KeyCode::Ae04,
            KeyCode::Ae05,
            KeyCode::Ae06,
            KeyCode::Ae07,
            KeyCode::Ae08,
            KeyCode::Ae09,
            KeyCode::Ae10,
            KeyCode::Ae11,
            KeyCode::Ae12,
            KeyCode::Bksl,
        ],
    },
    RowDescription {
        offset: 10,
        keys: &[
            KeyCode::Ad01,
            KeyCode::Ad02,
            KeyCode::Ad03,
            KeyCode::Ad04,
            KeyCode::Ad05,
            KeyCode::Ad06,
            KeyCode::Ad07,
            KeyCode::Ad08,
            KeyCode::Ad09,
            KeyCode::Ad10,
            KeyCode::Ad11,
            KeyCode::Ad12,
        ],
    },
    RowDescription {
        offset: 11,
        keys: &[
            KeyCode::Ac01,
            KeyCode::Ac02,
            KeyCode::Ac03,
            KeyCode::Ac04,
            KeyCode::Ac05,
            KeyCode::Ac06,
            KeyCode::Ac07,
            KeyCode::Ac08,
            KeyCode::Ac09,
            KeyCode::Ac10,
            KeyCode::Ac11,
        ],
    },
    RowDescription {
        offset: 14,
        keys: &[
            KeyCode::Ab01,
            KeyCode::Ab02,
            KeyCode::Ab03,
            KeyCode::Ab04,
            KeyCode::Ab05,
            KeyCode::Ab06,
            KeyCode::Ab07,
            KeyCode::Ab08,
            KeyCode::Ab09,
            KeyCode::Ab10,
        ],
    },
];
