use anyhow::Result;
use gmodx::lua::{self, Function, Table};

use super::{Param, QueryResult, parse_params};

#[derive(Debug, Copy, Clone)]
pub enum QueryType {
    Run,
    Execute,
    FetchOne,
    FetchAll,
}

#[derive(Debug)]
pub struct Query {
    pub query: String,
    pub qtype: QueryType,
    pub params: Vec<Param>,
    pub callback: Option<Function>,
    pub on_error: Option<Function>,
    pub raw: bool,
    pub result: Result<QueryResult>,
    pub trace: Option<lua::String>,
}

impl Query {
    pub fn new(
        state: &lua::State,
        query: String,
        qtype: QueryType,
        on_error: Option<Function>,
        opts: Option<Table>,
    ) -> Result<Self> {
        let mut this = Self {
            query,
            qtype,
            params: Vec::new(),
            callback: None,
            on_error,
            raw: false,
            result: Ok(QueryResult::Run),
            trace: None,
        };

        if let Some(opts) = opts {
            this.raw = opts.get::<Option<bool>>(state, "raw")?.unwrap_or(false);
            this.callback = opts.get(state, "callback")?;
            this.trace = opts.get(state, "trace")?;

            if let Some(params) = opts.get::<Option<Table>>(state, "params")? {
                this.params = parse_params(state, params)?;
            }
        }

        Ok(this)
    }
}
