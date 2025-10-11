use anyhow::Result;
use sqlx::{Executor, MySqlConnection, mysql::MySqlConnection as Conn};

use super::{
    Param, Query, QueryResult,
    result::{convert_row, convert_rows},
    types::QueryType,
};

pub async fn execute_query<'a, 'q, E>(
    query: E,
    conn: &'q mut Conn,
    query_type: &QueryType,
) -> Result<QueryResult>
where
    E: 'q + sqlx::Execute<'q, sqlx::MySql>,
{
    match query_type {
        QueryType::Run => {
            conn.execute(query).await?;
            Ok(QueryResult::Run)
        }
        QueryType::Execute => {
            let info = conn.execute(query).await?;
            Ok(QueryResult::Execute(info))
        }
        QueryType::FetchAll => {
            let rows = conn.fetch_all(query).await?;
            let rows = convert_rows(&rows);
            Ok(QueryResult::Rows(rows))
        }
        QueryType::FetchOne => {
            let row = conn.fetch_optional(query).await?;
            let row = convert_row(&row);
            Ok(QueryResult::Row(row))
        }
    }
}

impl Query {
    pub async fn start(&mut self, conn: &mut MySqlConnection) {
        let qtype = &self.qtype;

        if self.raw {
            // &str gets treated as raw query in sqlx
            self.result = execute_query(self.query.as_str(), conn, qtype).await;
        } else {
            let mut query = sqlx::query(self.query.as_str());

            for param in self.params.drain(..) {
                query = match param {
                    Param::Bool(b) => query.bind(b),
                    Param::Number(n) => query.bind(n),
                    Param::String(s) => query.bind::<Vec<u8>>(s.into()),
                };
            }

            self.result = execute_query(query, conn, qtype).await;
        }
    }
}
