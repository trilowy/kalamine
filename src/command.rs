use crate::model::{KeyboardGeometry, KeyboardLayout, OutputType};

pub fn build(layout_descriptor: String, out: OutputType, angle_mod: bool, qwerty_shortcuts: bool) {
    // TODO: build command
    // TODO: out may be also a path to a file
    println!(
        "build: layout_descriptor={layout_descriptor}, out={out:?}, angle_mod={angle_mod}, qwerty_shortcuts={qwerty_shortcuts}"
    );
    eprintln!("Feature not yet implemented");
}

pub fn new(output_file: String, geometry: KeyboardGeometry, altgr: bool, odk: bool) {
    // TODO: new command
    println!("new: output_file={output_file}, geometry={geometry:?}, altgr={altgr}, odk={odk}");
    eprintln!("Feature not yet implemented");
}

pub fn watch(file_path: String, angle_mod: bool) {
    // TODO: watch command
    println!("watch: file_path={file_path}, angle_mod={angle_mod}");
    eprintln!("Feature not yet implemented");
}

const MARKDOWN_HEADER: &str = include_str!("files/header.md");

pub fn guide() {
    // TODO: guide command
    println!("{MARKDOWN_HEADER}");
}

/// Draw a ASCII art description of a default layout
fn draw_layout(geometry: KeyboardGeometry, altgr: bool, odk: bool) -> String {
    // TODO:
    todo!()
}

/// Create a dummy (QWERTY) layout with the given characteristics
fn dummy_layout(geometry: KeyboardGeometry, altgr: bool, odk: bool) -> KeyboardLayout {
    // TODO:
    todo!()
}
