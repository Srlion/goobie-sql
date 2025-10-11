use const_format::{formatcp, str_index, str_replace};

const fn index_of_dot(s: &str) -> usize {
    let bytes = s.as_bytes();
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'.' {
            return i;
        }
        i += 1;
    }
    s.len() // if no dot is found, return the length of the string
}

pub const VERSION: &str = str_index!(
    env!("CARGO_PKG_VERSION"),
    ..env!("CARGO_PKG_VERSION").len() - 2
);
pub const MAJOR_VERSION: &str = str_index!(
    env!("CARGO_PKG_VERSION"),
    ..index_of_dot(env!("CARGO_PKG_VERSION"))
);

pub const GOOBIE_MYSQL_TABLE_NAME: &str =
    formatcp!("goobie_mysql_{}", str_replace!(MAJOR_VERSION, ".", "_"));

/// Session timeout in seconds. We ping every WAIT_TIMEOUT/2 to keep the connection alive.
pub const WAIT_TIMEOUT: u32 = 7200;
