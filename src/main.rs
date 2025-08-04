use clap::Parser;
use cli::ProgramArguments;

mod cli;
mod command;
mod lexer;
mod model;

fn main() {
    ProgramArguments::parse().run_command();
}
