use gmodx::lua::{self, Table};
use sqlx::mysql::MySqlDatabaseError;

use crate::GOOBIE_MYSQL_TABLE_NAME;

fn write_mysql_error_fields(state: &lua::State, err: &MySqlDatabaseError, out: &Table) -> String {
    if let Some(sqlstate) = err.code() {
        out.raw_set(state, "sqlstate", sqlstate);
    }
    out.raw_set(state, "code", err.number());
    err.message().to_string()
}

fn write_sqlx_error(state: &lua::State, err: &sqlx::Error, out: &Table) {
    let msg = match err {
        sqlx::Error::Database(db_e) => match db_e.try_downcast_ref::<MySqlDatabaseError>() {
            Some(mysql_e) => write_mysql_error_fields(state, mysql_e, out),
            _ => err.to_string(),
        },
        _ => err.to_string(),
    };

    out.raw_set(state, "message", &msg);
}

fn apply_error_metatable(state: &lua::State, tbl: &Table) {
    let goobie_mysql: Table = state
        .get_global(GOOBIE_MYSQL_TABLE_NAME)
        .unwrap_or_else(|_| panic!("Failed to get global '{GOOBIE_MYSQL_TABLE_NAME}'"));

    if let Some(meta) = goobie_mysql
        .get::<Option<Table>>(state, "ERROR_META")
        .expect("ERROR_META is supposed to be a table")
    {
        tbl.set_metatable(state, Some(&meta));
    }
}

pub fn to_error_table(state: &lua::State, err: &anyhow::Error) -> Table {
    let out = state.create_table_with_capacity(0, 3);

    if let Some(sqlx_err) = err.downcast_ref::<sqlx::Error>() {
        write_sqlx_error(state, sqlx_err, &out);
    } else {
        out.raw_set(state, "message", err.to_string());
    }

    apply_error_metatable(state, &out);
    out
}
