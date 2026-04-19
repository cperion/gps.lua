fn main() {
    let candidates = ["luajit", "luajit-5.1"];
    for name in candidates {
        if pkg_config::Config::new().probe(name).is_ok() {
            println!("cargo:rustc-cfg=has_luajit");
            return;
        }
    }
    panic!("could not find LuaJIT via pkg-config (tried: luajit, luajit-5.1)");
}
