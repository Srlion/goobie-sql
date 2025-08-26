use gmod::*;

mod conn;
mod constants;
mod error;
mod query;
mod runtime;

pub use constants::*;
pub use runtime::{run_async, spawn_untracked};

#[gmod13_open]
fn gmod13_open(l: lua::State) -> i32 {
    runtime::load(l);

    l.new_table();
    {
        l.push_string(crate::VERSION);
        l.set_field(-2, c"VERSION");

        l.push_string(crate::MAJOR_VERSION);
        l.set_field(-2, c"MAJOR_VERSION");

        l.push_function(conn::new_conn);
        l.set_field(-2, c"NewConn");
    }
    l.set_global(GLOBAL_TABLE_NAME_C);

    conn::on_gmod_open(l);

    0
}

#[gmod13_close]
fn gmod13_close(l: lua::State) -> i32 {
    runtime::unload(l);

    0
}

#[macro_export]
macro_rules! print_goobie {
    ($($arg:tt)*) => {
        println!("(Goobie MySQL v{}) {}", $crate::VERSION, format_args!($($arg)*));
    };
}

#[macro_export]
macro_rules! print_goobie_with_host {
    ($host:expr, $($arg:tt)*) => {
        println!("(Goobie MySQL v{}) |{}| {}", $crate::VERSION, $host, format_args!($($arg)*));
    };
}

#[macro_export]
macro_rules! cstr_from_args {
    ($($arg:expr),+) => {{
        use std::ffi::{c_char, CStr};
        const BYTES: &[u8] = const_format::concatcp!($($arg),+, "\0").as_bytes();
        let ptr: *const c_char = BYTES.as_ptr().cast();
        unsafe { CStr::from_ptr(ptr) }
    }};
}
