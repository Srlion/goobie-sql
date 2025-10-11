mod handler;
mod options;
mod reconnect;
mod types;
mod userdata;

use gmodx::lua::{self, Table, UserData};
pub use types::Conn;

pub fn on_gmod_open(state: &lua::State, goobie_mysql: &Table) {
    goobie_mysql.raw_set(state, "CONN_META", Conn::init_methods_table(state));
    goobie_mysql.raw_set(state, "NewConn", state.create_function(Conn::new));
}
