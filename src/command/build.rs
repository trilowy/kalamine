use crate::model::OutputType;

pub fn run(layout_descriptor: String, out: OutputType, angle_mod: bool, qwerty_shortcuts: bool) {
    // TODO: build command
    // TODO: out may be also a path to a file
    println!(
        "build: layout_descriptor={layout_descriptor}, out={out:?}, angle_mod={angle_mod}, qwerty_shortcuts={qwerty_shortcuts}"
    );
    eprintln!("Feature not yet implemented");
}
