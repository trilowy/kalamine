use crate::model::{KeyboardGeometry, KeyboardLayout, OutputType};

pub fn build(layout_descriptor: String, out: OutputType, angle_mod: bool, qwerty_shortcuts: bool) {
    // TODO
    println!(
        "build: layout_descriptor={}, out={:?}, angle_mod={}, qwerty_shortcuts={}",
        layout_descriptor, out, angle_mod, qwerty_shortcuts
    );
    eprintln!("Feature not yet implemented");
}

pub fn new(output_file: String, geometry: KeyboardGeometry, altgr: bool, odk: bool) {
    // TODO
    println!(
        "new: output_file={}, geometry={:?}, altgr={}, odk={}",
        output_file, geometry, altgr, odk
    );
    eprintln!("Feature not yet implemented");
}

pub fn watch(file_path: String) {
    // TODO
    println!("watch: file_path={}", file_path);
    eprintln!("Feature not yet implemented");
}

const MARKDOWN_HEADER: &str = include_str!("files/header.md");

pub fn guide() {
    // TODO
    println!("{MARKDOWN_HEADER}");
}

/// Draw a ASCII art description of a default layout
fn draw_layout(geometry: KeyboardGeometry, altgr: bool, odk: bool) -> String {
    todo!()
}

/// Create a dummy (QWERTY) layout with the given characteristics
fn dummy_layout(geometry: KeyboardGeometry, altgr: bool, odk: bool) -> KeyboardLayout {
    todo!()
}
