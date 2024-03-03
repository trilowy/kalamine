use crate::{
    command::{build, guide, new, watch},
    model::{KeyboardGeometry, OutputType},
};
use clap::{Parser, Subcommand};

/// Kalamine, a keyboard layout maker
#[derive(Parser, Debug)]
#[command(version, about, long_about = None)]
pub struct ProgramArguments {
    #[clap(subcommand)]
    action: Command,
}

#[derive(Subcommand, Debug)]
enum Command {
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

        /// Keep shortcuts at their qwerty location
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
    },
    /// Show user guide
    Guide,
}

impl ProgramArguments {
    pub fn run_command(self) {
        match self.action {
            Command::Build {
                layout_descriptor,
                out,
                angle_mod,
                qwerty_shortcuts,
            } => {
                build(layout_descriptor, out, angle_mod, qwerty_shortcuts);
            }
            Command::New {
                output_file,
                geometry,
                altgr,
                odk,
            } => {
                new(output_file, geometry, altgr, odk);
            }
            Command::Watch { file_path } => {
                watch(file_path);
            }
            Command::Guide => {
                guide();
            }
        }
    }
}
