use clap::Parser;
use cli::ProgramArguments;

mod cli;
mod command;
mod model;

fn main() {
    ProgramArguments::parse().run_command();
}
