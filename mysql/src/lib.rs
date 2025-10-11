use gmodx::{gmod13_close, gmod13_open, lua, tokio_tasks};

mod config;
mod connection;
mod error;
mod macros;
mod query;
mod state;

pub use config::*;

#[gmod13_open]
fn gmod13_open(state: lua::State) {
    let goobie_mysql = state.create_table();

    goobie_mysql.raw_set(&state, "VERSION", VERSION);
    goobie_mysql.raw_set(&state, "MAJOR_VERSION", MAJOR_VERSION);

    connection::on_gmod_open(&state, &goobie_mysql);
    crate::state::on_gmod_open(&state, &goobie_mysql);

    state
        .set_global(GOOBIE_MYSQL_TABLE_NAME, goobie_mysql)
        .expect("Failed to set goobie_mysql table");

    tokio_tasks::on_event(|event| {
        use gmodx::tokio_tasks::RuntimeEvent;
        match event {
            RuntimeEvent::Starting { thread_count } => {
                print_goobie!("Using {thread_count} async threads! (GMODX_ASYNC_THREADS)");
            }
            RuntimeEvent::ShuttingDown {
                timeout_secs,
                pending_tasks,
            } => {
                if pending_tasks > 0 {
                    print_goobie!(
                        "Waiting up to {timeout_secs} seconds for {pending_tasks} connection(s) to complete..."
                    );
                }
            }
            RuntimeEvent::ShutdownComplete => {
                print_goobie!("All connections have completed!");
            }
            RuntimeEvent::ShutdownTimeout => {
                print_goobie!("Timed out waiting for connections to complete!");
            }
        }
    });
}

#[gmod13_close]
fn gmod13_close(state: lua::State) {}
