use gmod::*;

use crate::{cstr_from_args, VERSION};

pub const GLOBAL_TABLE_NAME: &str = {
    const VERSION_UNDERSCORE: &str = {
        const LEN: usize = VERSION.len();
        const fn format_version(input: &str) -> [u8; LEN] {
            let bytes = input.as_bytes();
            let mut output = [0u8; LEN];
            let mut i = 0;
            while i < LEN {
                output[i] = if bytes[i] == b'.' { b'_' } else { bytes[i] };
                i += 1;
            }
            output
        }

        const OUTPUT: [u8; LEN] = format_version(VERSION);
        unsafe { std::str::from_utf8_unchecked(&OUTPUT) }
    };
    constcat::concat!("goobie_mysql_", VERSION_UNDERSCORE)
};
pub const GLOBAL_TABLE_NAME_C: LuaCStr = cstr_from_args!(GLOBAL_TABLE_NAME);
