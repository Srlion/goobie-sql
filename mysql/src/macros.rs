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
