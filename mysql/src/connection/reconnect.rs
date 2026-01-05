use anyhow::anyhow;
use gmodx::lua::{LuaResultExt, Nil};
use sqlx::{Connection, mysql::MySqlConnection};
use std::{sync::atomic::Ordering, time::Duration};

use crate::{
    config, error::to_error_table, print_goobie_with_host, query::QueryResult, state::State,
};

use super::types::ConnMeta;

const CONNECT_TIMEOUT: Duration = Duration::from_secs(5);
const MAX_ATTEMPTS: u32 = 3;
const RETRY_DELAY: Duration = Duration::from_secs(2);

async fn connect_with_retry(
    opts: &sqlx::mysql::MySqlConnectOptions,
) -> Result<MySqlConnection, sqlx::Error> {
    let mut last_err = None;
    for _ in 1..=MAX_ATTEMPTS {
        match tokio::time::timeout(CONNECT_TIMEOUT, MySqlConnection::connect_with(opts)).await {
            Ok(Ok(conn)) => return Ok(conn),
            Ok(Err(e)) => {
                last_err = Some(e);
            }
            Err(_) => {
                last_err = Some(sqlx::Error::PoolTimedOut);
            }
        }
        tokio::time::sleep(RETRY_DELAY).await;
    }
    Err(last_err.unwrap())
}

pub async fn connect(
    db_conn: &mut Option<MySqlConnection>,
    meta: &ConnMeta,
    callback: Option<gmodx::lua::Function>,
) -> bool {
    if let Some(old_conn) = db_conn.take() {
        // let's gracefully close the connection if there is any
        // we don't care if it fails, as we are reconnecting anyway
        let _ = old_conn.close().await;
    }

    meta.state.set(State::Connecting);

    let res = match connect_with_retry(&meta.opts).await {
        Ok(mut new_conn) => {
            let wait_timeout = config::WAIT_TIMEOUT;
            sqlx::query(&format!("SET SESSION wait_timeout = {}", wait_timeout))
                .execute(&mut new_conn)
                .await
                .ok();

            *db_conn = Some(new_conn);
            meta.id.fetch_add(1, Ordering::Release);
            meta.state.set(State::Connected);
            Ok(())
        }
        Err(e) => {
            meta.state.set(State::NotConnected);
            Err(e)
        }
    };

    let success = res.is_ok();

    if let Some(callback) = callback {
        gmodx::next_tick(move |state: &gmodx::lua::State| {
            match res {
                Ok(()) => callback.call::<()>(state, ()).log(),
                Err(e) => callback.call(state, to_error_table(state, &e.into())).log(),
            };
        });
    }

    success
}

fn should_reconnect(err: &anyhow::Error) -> bool {
    let sqlx_e = match err.downcast_ref::<sqlx::Error>() {
        Some(e) => e,
        None => return false,
    };

    match sqlx_e {
        sqlx::Error::Io(io_err) => matches!(
            io_err.kind(),
            std::io::ErrorKind::ConnectionRefused
                | std::io::ErrorKind::ConnectionReset
                | std::io::ErrorKind::ConnectionAborted
                | std::io::ErrorKind::NotConnected
                | std::io::ErrorKind::TimedOut
                | std::io::ErrorKind::BrokenPipe
                | std::io::ErrorKind::UnexpectedEof
        ),
        sqlx::Error::Tls(tls_err) => {
            let msg = tls_err.to_string();
            msg.contains("handshake failed")
                || msg.contains("connection closed")
                || msg.contains("unexpected EOF")
        }
        sqlx::Error::Database(db_err) => {
            if let Some(mysql_err) = db_err.try_downcast_ref::<sqlx::mysql::MySqlDatabaseError>() {
                matches!(mysql_err.number(), 2002 | 2003 | 2006 | 2013 | 2055)
            } else {
                false
            }
        }
        _ => false,
    }
}

pub async fn query(
    conn: &mut Option<MySqlConnection>,
    meta: &ConnMeta,
    mut query: crate::query::Query,
) {
    let db_conn = match conn {
        Some(conn) => conn,
        None => {
            if let Some(callback) = query.callback {
                gmodx::next_tick(move |state| {
                    callback
                        .call::<()>(
                            state,
                            to_error_table(state, &anyhow!("connection is not open")),
                        )
                        .log();
                });
            }
            return;
        }
    };

    query.start(db_conn).await;

    let should_reconnect = if let Err(e) = query.result.as_ref() {
        let should = should_reconnect(e);
        // we need to actually ping the connection, as extra validation that the connection is actually dead to not mess up with any queries
        if should && db_conn.ping().await.is_err() {
            // make sure that it's set before we return back to lua
            // this is a MUST because if we are inside a transaction and reconnect, lua MUST forget about the transaction
            // it can cause issues if we reconnect and lua thinks it's still in a transaction
            // we do it by changing the state AND having a unique id for each inner connection
            // this way a transaction can check the state AND the id to know if it's still in a transaction
            // if it's not, it can forget about it completely
            meta.state.set(State::NotConnected);
            print_goobie_with_host!(
                meta.opts.get_host(),
                "Database connection is lost, reconnecting..."
            );
        }

        should
    } else {
        false
    };

    handle_query_result(query);

    if should_reconnect {
        attempt_reconnect(conn, meta).await;
    }
}

fn handle_query_result(query: crate::query::Query) {
    gmodx::next_tick(move |state| match &query.result {
        Ok(query_result) => {
            let Some(callback) = query.callback else {
                return;
            };
            use QueryResult::*;
            match query_result {
                Run => {
                    callback.call::<()>(state, ()).log();
                }
                Execute(info) => {
                    let info_table = state.create_table_with_capacity(0, 2);
                    info_table.raw_set(state, "rows_affected", info.rows_affected());
                    info_table.raw_set(state, "last_insert_id", info.last_insert_id());
                    callback.call::<()>(state, (Nil, info_table)).log();
                }
                Rows(rows) => {
                    let rows = match rows {
                        Ok(rows) => rows,
                        Err(err) => {
                            callback.call::<()>(state, to_error_table(state, err)).log();
                            return;
                        }
                    };

                    let rows_table = state.create_table_with_capacity(rows.len() as i32, 0);
                    for (idx, row) in rows.iter().enumerate() {
                        let row_table = state.create_table_with_capacity(0, row.len() as i32);
                        for value in row.iter() {
                            row_table.raw_set(state, &value.column_name, &value.value);
                        }
                        rows_table.raw_set(state, idx as i32 + 1, &row_table);
                    }
                    callback.call::<()>(state, (Nil, rows_table)).log();
                }
                Row(row) => {
                    let row = match row {
                        Ok(Some(row)) => row,
                        Ok(None) => {
                            callback.call::<()>(state, ()).log();
                            return;
                        }
                        Err(err) => {
                            callback.call::<()>(state, to_error_table(state, err)).log();
                            return;
                        }
                    };

                    let row_table = state.create_table_with_capacity(0, row.len() as i32);
                    for column_value in row.iter() {
                        row_table.raw_set(state, &column_value.column_name, &column_value.value);
                    }
                    callback.call::<()>(state, (Nil, row_table)).log();
                }
            }
        }
        Err(err) => {
            if let Some(on_error) = query.on_error {
                on_error
                    .call::<()>(state, (to_error_table(state, err), query.trace))
                    .log();
            }

            if let Some(callback) = query.callback {
                callback.call::<()>(state, to_error_table(state, err)).log();
            }
        }
    });
}

async fn attempt_reconnect(conn: &mut Option<MySqlConnection>, meta: &ConnMeta) {
    let mut delay = Duration::from_secs(2);
    let mut reconnected = false;

    for _ in 0..7 {
        tokio::time::sleep(delay).await;
        delay += Duration::from_secs(1);

        if connect(conn, meta, None).await {
            print_goobie_with_host!(meta.opts.get_host(), "Reconnected!");
            reconnected = true;
            break;
        } else {
            print_goobie_with_host!(
                meta.opts.get_host(),
                "Failed to reconnect, retrying in {} seconds...",
                delay.as_secs()
            );
        }
    }

    if !reconnected {
        print_goobie_with_host!(meta.opts.get_host(), "Failed to reconnect, giving up!");
    }
}
