use anyhow::Result;
use gmodx::lua::{self, Function, ObjectLike as _, Table, TypedUserData, UserData, UserDataRef};

use crate::query;

use super::types::{Conn, ConnMessage};

impl UserData for Conn {
    fn meta_methods(methods: &mut lua::Methods) {
        methods.add(c"__tostring", |_: &lua::State, conn: UserDataRef<Conn>| {
            conn.borrow().to_string()
        });
    }

    fn methods(methods: &mut lua::Methods) {
        methods.add(
            c"Start",
            |_: &lua::State, conn: UserDataRef<Conn>, callback: Function| {
                conn.borrow()
                    .sender
                    .send(ConnMessage::Connect(Some(callback)))
                    .ok();
            },
        );

        methods.add(
            c"Disconnect",
            |_: &lua::State, conn: UserDataRef<Conn>, callback: Option<Function>| {
                conn.borrow()
                    .sender
                    .send(ConnMessage::Disconnect(callback))
                    .ok();
            },
        );

        methods.add(c"State", |_: &lua::State, conn: UserDataRef<Conn>| {
            conn.borrow().state() as usize
        });

        methods.add(
            c"Ping",
            |_: &lua::State, conn: UserDataRef<Conn>, callback: Function| {
                conn.borrow()
                    .sender
                    .send(ConnMessage::Ping(Some(callback)))
                    .ok();
            },
        );

        methods.add(c"Run", create_query_func(query::QueryType::Run));
        methods.add(c"Execute", create_query_func(query::QueryType::Execute));
        methods.add(c"FetchOne", create_query_func(query::QueryType::FetchOne));
        methods.add(c"Fetch", create_query_func(query::QueryType::FetchAll));

        methods.add(c"ID", |_: &lua::State, conn: UserDataRef<Conn>| {
            conn.borrow().id()
        });

        methods.add(c"Host", |_: &lua::State, conn: UserDataRef<Conn>| {
            conn.borrow().meta.opts.get_host().to_string()
        });

        methods.add(c"Port", |_: &lua::State, conn: UserDataRef<Conn>| {
            conn.borrow().meta.opts.get_port()
        });

        methods.add(c"Poll", |state: &lua::State, conn: UserDataRef<Conn>| {
            conn.borrow().poll(state)
        });
    }
}

fn create_query_func(
    qtype: query::QueryType,
) -> impl Fn(&lua::State, TypedUserData<Conn>, lua::String, Option<Table>) -> Result<()> {
    move |state: &lua::State,
          conn_ud: TypedUserData<Conn>,
          query: lua::String,
          opts: Option<Table>|
          -> Result<()> {
        let conn = conn_ud.downcast::<Conn>(state).expect("check");
        let on_error = conn_ud.get::<Option<Function>>(state, "on_error")?;
        let query = query::Query::new(state, query.to_string(), qtype, on_error, opts)?;
        conn.borrow().sender.send(ConnMessage::Query(query)).ok();
        Ok(())
    }
}
