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
