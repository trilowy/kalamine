use crate::{layout::KeyboardGeometry, model::OutputType};
use clap::{Parser, Subcommand};

#[derive(Parser, Debug)]
#[command(version, about, long_about = None)]
pub struct ProgramArguments {
    #[clap(subcommand)]
    pub action: Command,
}

#[derive(Subcommand, Debug)]
pub enum Command {
    /// Convert TOML/YAML description into OS-specific keyboard drivers
    Build {
        /// TOML/YAML description path
        layout_descriptor: String,

        /// Type of keyboard drivers to generate
        #[clap(short, long, default_value_t)]
        #[arg(value_enum)]
        out: OutputType,

        /// Apply angle-mod, which is a [ZXCVB] permutation with the LSGT key (a.k.a. ISO key)
        #[clap(short, long)]
        angle_mod: bool,

        /// Keep shortcuts at their QWERTY location
        #[clap(short, long)]
        qwerty_shortcuts: bool,
    },

    /// Create a new TOML layout description
    New {
        /// Output file path
        output_file: String,

        /// Specify keyboard geometry
        #[clap(short, long, default_value_t)]
        #[arg(value_enum)]
        geometry: KeyboardGeometry,

        /// Set an AltGr layer
        #[clap(short, long)]
        altgr: bool,

        /// Set a custom dead key
        #[clap(short, long)]
        odk: bool,
    },

    /// Watch a layout description file and display it in a web browser
    Watch {
        /// Path to the file to watch
        file_path: String,

        /// Apply angle-mod, which is a [ZXCVB] permutation with the LSGT key (a.k.a. ISO key)
        #[clap(short, long)]
        angle_mod: bool,
    },

    /// Show user guide
    Guide,
}
