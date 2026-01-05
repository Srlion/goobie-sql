use anyhow::anyhow;
use gmodx::lua::{LuaResultExt, Nil};
use sqlx::Connection;
use sqlx::mysql::MySqlConnection;
use std::sync::Arc;
use tokio::sync::mpsc;

use crate::state::State;

use super::{
    reconnect,
    types::{ConnMessage, ConnMeta},
};

pub async fn handle_messages(
    mut receiver: mpsc::UnboundedReceiver<ConnMessage>,
    meta: Arc<ConnMeta>,
) {
    let mut db_conn: Option<MySqlConnection> = None;

    while let Some(msg) = receiver.recv().await {
        match msg {
            ConnMessage::Connect(callback) => {
                reconnect::connect(&mut db_conn, &meta, callback).await;
            }
            ConnMessage::Disconnect(callback) => {
                disconnect(&mut db_conn, &meta, callback).await;
            }
            ConnMessage::Query(query) => {
                reconnect::query(&mut db_conn, &meta, query).await;
            }
            ConnMessage::Ping(callback) => {
                ping(&mut db_conn, callback).await;
            }
            // This should be called after "disconnect"
            ConnMessage::Close => {
                break;
            }
        }
    }
}

async fn disconnect(
    db_conn: &mut Option<MySqlConnection>,
    meta: &ConnMeta,
    callback: Option<gmodx::lua::Function>,
) {
    meta.state.set(State::Disconnected);

    let res = match db_conn.take() {
        Some(old_conn) => old_conn.close().await,
        None => Ok(()),
    };

    let Some(callback) = callback else {
        return;
    };

    gmodx::next_tick(move |state: &gmodx::lua::State| {
        match res {
            Ok(()) => callback.call::<()>(state, ()).log(),
            Err(e) => callback
                .call(state, crate::error::to_error_table(state, &e.into()))
                .log(),
        };
    });
}

async fn ping(db_conn: &mut Option<MySqlConnection>, callback: Option<gmodx::lua::Function>) {
    let db_conn = match db_conn {
        Some(conn) => conn,
        None => {
            if let Some(callback) = callback {
                gmodx::next_tick(move |state| {
                    callback
                        .call::<()>(
                            state,
                            crate::error::to_error_table(state, &anyhow!("connection is not open")),
                        )
                        .log();
                });
            }
            return;
        }
    };

    let start = tokio::time::Instant::now();
    let res = db_conn.ping().await;
    let latency = start.elapsed().as_micros() as f64;

    let Some(callback) = callback else {
        return;
    };

    gmodx::next_tick(move |state: &gmodx::lua::State| {
        match res {
            Ok(()) => callback.call::<()>(state, (Nil, latency)).log(),
            Err(e) => callback
                .call(state, crate::error::to_error_table(state, &e.into()))
                .log(),
        };
    });
}
