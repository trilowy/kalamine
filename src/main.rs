use crate::{
    cli::{Command, ProgramArguments},
    command::{build, guide, new, watch},
};
use clap::Parser;

mod cli;
mod command;
mod layout;
mod lexer;

fn main() {
    let command = ProgramArguments::parse();

    match command.action {
        Command::Build {
            layout_descriptor,
            out,
            angle_mod,
            qwerty_shortcuts,
        } => {
            build::run(layout_descriptor, out, angle_mod, qwerty_shortcuts);
        }

        Command::New {
            output_file,
            geometry,
            altgr,
            odk,
        } => {
            new::run(output_file, geometry, altgr, odk);
        }

        Command::Watch {
            file_path,
            angle_mod,
        } => {
            watch::run(file_path, angle_mod);
        }

        Command::Guide => {
            guide::run();
        }
    }
}
