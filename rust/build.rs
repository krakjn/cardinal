fn main() {
    eprintln!("build.rs: Starting build script");
    
    // Tell cargo to look for shared libraries in the build directory
    println!("cargo:rustc-link-search=native=../build");
    println!("cargo:rustc-link-search=native=/usr/local/lib");
    
    // Link against the pre-built FastDDS wrapper static library
    println!("cargo:rustc-link-lib=static=cardinal-fastdds");
    
    // Link against FastDDS libraries - order matters
    println!("cargo:rustc-link-lib=dylib=fastdds");
    println!("cargo:rustc-link-lib=dylib=fastcdr");
    println!("cargo:rustc-link-lib=dylib=stdc++");
    
    // Tell cargo to invalidate the built crate whenever the wrapper changes
    println!("cargo:rerun-if-changed=../build/libcardinal-fastdds.a");
    println!("cargo:rerun-if-changed=../lib/fastdds.cpp");
    println!("cargo:rerun-if-changed=../lib/fastdds.h");
    
    eprintln!("build.rs: Build script completed");
}