use crate::layout::{Geometry, KeyboardLayout};
use anyhow::Result;

/// Create a new TOML layout description
pub fn run(output_file: String, geometry: Geometry, altgr: bool, odk: bool) {
    // TODO: new command
    println!("new: output_file={output_file}, geometry={geometry:?}, altgr={altgr}, odk={odk}");
    eprintln!("Feature not yet implemented");

    // TODO: at the end, check if the result is the same than the Python version
    // TODO: replace stdout by a file and put it nearer to were it is used

    // Make a KeyboardLayout, just to get the ASCII arts
    // const keyboard_layout = dummy_layout(&options);
    // // var keyboard_layout = dummyLayout(allocator, &options, parse_options) catch |err| {
    // //     return diag.report(stdout, err);
    // //     // TODO: no error for new layout but report error at higher level for build
    // // };
    // std.debug.print("parse\n{any}\n", .{keyboard_layout});
    //
    // try stdout.writeAll(DUMMY_METADATA);
    // try stdout.print(DUMMY_GEOMETRY, .{@tagName(options.geometry)});
    // keyboard_layout.geometry = options.geometry;

    // Write an ASCII art description of a default layout
    // TODO: kalamine/help.py:145
    // TODO: kalamine/help.py:111
    // const base = if (options.odk) DUMMY_ODK_LAYOUT else DUMMY_ALPHA_LAYOUT;
    // const base = try toml_generator.getBase(allocator, &keyboard_layout);
    // defer allocator.free(base);
    //
    // try stdout.print(DUMMY_LAYER, .{ "base", base });
    //
    // if (options.altgr) {
    //     // TODO:
    //     // try stdout.print(DUMMY_LAYER, .{ "altgr", DUMMY_ALTGR_LAYOUT });
    //     const altgr = try toml_generator.getAltgr(allocator, &keyboard_layout);
    //     defer allocator.free(altgr);
    //
    //     try stdout.print(DUMMY_LAYER, .{ "altgr", altgr });
    // }

    // TODO: kalamine/help.py:96 web scan codes
}

/// Create a dummy (QWERTY) layout with the given characteristics
fn dummy_layout(odk: bool, altgr: bool) -> Result<KeyboardLayout> {
    let base = if odk {
        DUMMY_ODK_LAYOUT
    } else {
        DUMMY_ALPHA_LAYOUT
    };

    let mut file_content = format!(
        r#"
# kalamine keyboard layout descriptor
name        = "Qwerty-custom"  # full layout name, displayed in the keyboard settings
name8       = "custom"         # short Windows filename: no spaces, no special chars
locale      = "en-US"          # locale/language id
variant     = "custom"         # layout variant id
author      = "nobody"         # author name
description = "Custom QWERTY layout"
url         = "https://github.com/OneDeadKey/kalamine"
version     = "0.0.1"
geometry    = "ANSI"

base = '''
{}
'''
"#,
        base
    );

    if altgr {
        file_content += &format!(
            r#"

altgr = '''
{}
'''
"#,
            DUMMY_ALTGR_LAYOUT
        );
    }

    // TODO: reader in Rust? TOML?
    // var reader = std.Io.Reader.fixed(file_content.items);
    // return KeyboardLayout.initFromToml(allocator, &reader, parse_options);
    todo!()
}

const DUMMY_ALPHA_LAYOUT: &str = r#"
┌─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┲━━━━━━━━━━┓
│ ~   │ !   │ @   │ #   │ $   │ %   │ ^   │ &   │ *   │ (   │ )   │ _   │ +   ┃          ┃
│ `   │ 1   │ 2   │ 3   │ 4   │ 5   │ 6   │ 7   │ 8   │ 9   │ 0   │ -   │ =   ┃ ⌫        ┃
┢━━━━━┷━━┱──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┺━━┯━━━━━━━┩
┃        ┃ Q   │ W   │ E   │ R   │ T   │ Y   │ U   │ I   │ O   │ P   │ {   │ }   │ |     │
┃ ↹      ┃     │     │     │     │     │     │     │     │     │     │ [   │ ]   │ \     │
┣━━━━━━━━┻┱────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┲━━━━┷━━━━━━━┪
┃         ┃ A   │ S   │ D   │ F   │ G   │ H   │ J   │ K   │ L   │ :   │ "   ┃            ┃
┃ ⇬       ┃     │     │     │     │     │     │     │     │     │ ;   │ '   ┃ ⏎          ┃
┣━━━━━━━━━┻━━┱──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┲━━┻━━━━━━━━━━━━┫
┃            ┃ Z   │ X   │ C   │ V   │ B   │ N   │ M   │ <   │ >   │ ?   ┃               ┃
┃ ⇧          ┃     │     │     │     │     │     │     │ ,   │ .   │ /   ┃ ⇧             ┃
┣━━━━━━━┳━━━━┻━━┳━━┷━━━━┱┴─────┴─────┴─────┴─────┴─────┴─┲━━━┷━━━┳━┷━━━━━╋━━━━━━━┳━━━━━━━┫
┃       ┃       ┃       ┃                                ┃       ┃       ┃       ┃       ┃
┃ Ctrl  ┃ super ┃ Alt   ┃ ␣                              ┃ Alt   ┃ super ┃ menu  ┃ Ctrl  ┃
┗━━━━━━━┻━━━━━━━┻━━━━━━━┹────────────────────────────────┺━━━━━━━┻━━━━━━━┻━━━━━━━┻━━━━━━━┛
"#;

const DUMMY_ODK_LAYOUT: &str = r#"
┌─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┲━━━━━━━━━━┓
│ ~   │ !   │ @   │ #   │ $   │ %   │ ^   │ &   │ *   │ (   │ )   │ _   │ +   ┃          ┃
│ `   │ 1   │ 2 « │ 3 » │ 4   │ 5 € │ 6   │ 7   │ 8   │ 9   │ 0   │ -   │ =   ┃ ⌫        ┃
┢━━━━━┷━━┱──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┺━━┯━━━━━━━┩
┃        ┃ Q   │ W   │ E   │ R   │ T   │ Y   │ U   │ I   │ O   │ P   │ {   │ }   │ |     │
┃ ↹      ┃     │     │   é │     │     │   ý │   ú │   í │   ó │     │ [   │ ]   │ \     │
┣━━━━━━━━┻┱────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┲━━━━┷━━━━━━━┪
┃         ┃ A   │ S   │ D   │ F   │ G   │ H   │ J   │ K   │ L   │ :   │*¨   ┃            ┃
┃ ⇬       ┃   á │     │     │     │     │     │     │     │     │ ;   │** ' ┃ ⏎          ┃
┣━━━━━━━━━┻━━┱──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┲━━┻━━━━━━━━━━━━┫
┃            ┃ Z   │ X   │ C   │ V   │ B   │ N   │ M   │ < • │ >   │ ?   ┃               ┃
┃ ⇧          ┃     │     │   ç │     │     │     │   µ │ , · │ . … │ /   ┃ ⇧             ┃
┣━━━━━━━┳━━━━┻━━┳━━┷━━━━┱┴─────┴─────┴─────┴─────┴─────┴─┲━━━┷━━━┳━┷━━━━━╋━━━━━━━┳━━━━━━━┫
┃       ┃       ┃       ┃                                ┃       ┃       ┃       ┃       ┃
┃ Ctrl  ┃ super ┃ Alt   ┃ ␣                              ┃ Alt   ┃ super ┃ menu  ┃ Ctrl  ┃
┗━━━━━━━┻━━━━━━━┻━━━━━━━┹────────────────────────────────┺━━━━━━━┻━━━━━━━┻━━━━━━━┻━━━━━━━┛
"#;

const DUMMY_ALTGR_LAYOUT: &str = r#"
┌─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┲━━━━━━━━━━┓
│  *~ │     │     │     │     │     │     │     │     │     │     │     │     ┃          ┃
│  *` │     │     │     │     │     │  *^ │     │     │     │     │     │     ┃ ⌫        ┃
┢━━━━━┷━━┱──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┺━━┯━━━━━━━┩
┃        ┃     │     │     │     │     │     │     │     │     │     │     │     │       │
┃ ↹      ┃   @ │   < │   > │   $ │   % │   ^ │   & │   * │   ' │   ` │     │     │       │
┣━━━━━━━━┻┱────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┬────┴┲━━━━┷━━━━━━━┪
┃         ┃     │     │     │     │     │     │     │     │     │     │  *¨ ┃            ┃
┃ ⇬       ┃   { │   ( │   ) │   } │   = │   \ │   + │   - │   / │   " │  *´ ┃ ⏎          ┃
┣━━━━━━━━━┻━━┱──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┲━━┻━━━━━━━━━━━━┫
┃            ┃     │     │     │     │     │     │     │     │     │     ┃               ┃
┃ ⇧          ┃   ~ │   [ │   ] │   _ │   # │   | │   ! │   ; │   : │   ? ┃ ⇧             ┃
┣━━━━━━━┳━━━━┻━━┳━━┷━━━━┱┴─────┴─────┴─────┴─────┴─────┴─┲━━━┷━━━┳━┷━━━━━╋━━━━━━━┳━━━━━━━┫
┃       ┃       ┃       ┃                                ┃       ┃       ┃       ┃       ┃
┃ Ctrl  ┃ super ┃ Alt   ┃ ␣                              ┃ AltGr ┃ super ┃ menu  ┃ Ctrl  ┃
┗━━━━━━━┻━━━━━━━┻━━━━━━━┹────────────────────────────────┺━━━━━━━┻━━━━━━━┻━━━━━━━┻━━━━━━━┛
"#;
// FIXME: Alt should not be named AltGr
