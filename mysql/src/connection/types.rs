use anyhow::Result;
use sqlx::mysql::MySqlConnectOptions;
use std::sync::{
    Arc,
    atomic::{AtomicUsize, Ordering},
};
use tokio::sync::mpsc;

use gmodx::{
    NextTickQueue,
    lua::{self, Function, Table},
    tokio_tasks::spawn_untracked,
};

use crate::{
    WAIT_TIMEOUT, query,
    state::{AtomicState, State},
};

use super::{handler, options};

pub enum ConnMessage {
    Connect(Option<Function>),
    Disconnect(Option<Function>),
    Query(query::Query),
    Ping(Option<Function>),
    Close,
}

pub struct ConnMeta {
    // each connection needs a unique id for each inner connection
    // this is to be used for transactions to know if they are still in a transaction or not
    // if it's a new connection, it's not in a transaction, so it MUST forget about it
    // we don't use the state alone because it could switch back to Connected quickly and the
    // transaction would think it's still in a transaction
    pub id: AtomicUsize,
    pub state: AtomicState,
    pub opts: MySqlConnectOptions,
    pub task_queue: NextTickQueue,
}

pub struct Conn {
    pub meta: Arc<ConnMeta>,
    pub sender: mpsc::UnboundedSender<ConnMessage>,
}

impl Conn {
    pub fn new(state: &lua::State, opts: Table) -> Result<Self> {
        let opts = options::parse(state, opts)?;
        let (sender, receiver) = mpsc::unbounded_channel();

        let conn = Conn {
            meta: Arc::new(ConnMeta {
                id: AtomicUsize::new(0),
                state: AtomicState::new(State::NotConnected),
                opts,
                task_queue: NextTickQueue::new(state),
            }),
            sender,
        };

        let meta = conn.meta.clone();
        gmodx::tokio_tasks::spawn(async move {
            handler::handle_messages(receiver, meta).await;
        });

        conn.spawn_ping_heartbeat();

        Ok(conn)
    }

    #[inline]
    pub fn id(&self) -> usize {
        self.meta.id.load(Ordering::Acquire)
    }

    #[inline]
    pub fn state(&self) -> State {
        self.meta.state.get()
    }

    #[inline]
    pub fn poll(&self, state: &lua::State) {
        self.meta.task_queue.flush(state);
    }

    fn spawn_ping_heartbeat(&self) {
        let sender = self.sender.clone();
        spawn_untracked(async move {
            loop {
                // Try to send; if the receiver closed, exit.
                if sender.send(ConnMessage::Ping(None)).is_err() {
                    break;
                }
                tokio::time::sleep(std::time::Duration::from_secs((WAIT_TIMEOUT / 2).into())).await;
            }
        });
    }
}

impl Drop for Conn {
    fn drop(&mut self) {
        let _ = self.sender.send(ConnMessage::Disconnect(None));
        let _ = self.sender.send(ConnMessage::Close);
    }
}

impl std::fmt::Display for Conn {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        write!(
            f,
            "Goobie MySQL Connection [ID: {} | IP: {} | Port: {} | State: {}]",
            self.id(),
            self.meta.opts.get_host(),
            self.meta.opts.get_port(),
            self.state()
        )
    }
}
