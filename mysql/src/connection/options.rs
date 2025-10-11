use anyhow::{Result, bail};
use gmodx::lua::{self, Table};
use sqlx::mysql::MySqlConnectOptions;

pub fn parse(state: &lua::State, opts: Table) -> Result<MySqlConnectOptions> {
    let get_string = |primary: &str, fallback: Option<&str>| -> Result<Option<String>> {
        Ok(opts
            .get::<Option<lua::String>>(state, primary)?
            .or(fallback.and_then(|fb| opts.get::<Option<lua::String>>(state, fb).ok()?))
            .map(|s| s.to_string()))
    };

    let mut mysql_opts = match get_string("uri", None)? {
        Some(uri) => uri.to_string().parse()?,
        None => MySqlConnectOptions::new(),
    };

    if let Some(host) = get_string("host", Some("hostname"))? {
        mysql_opts = mysql_opts.host(&host);
    }

    if let Some(user) = get_string("user", Some("username"))? {
        mysql_opts = mysql_opts.username(&user);
    }

    if let Some(database) = get_string("database", Some("db"))? {
        mysql_opts = mysql_opts.database(&database);
    }

    if let Some(password) = get_string("password", Some("pass"))? {
        mysql_opts = mysql_opts.password(&password);
    }

    if let Some(charset) = get_string("charset", None)? {
        mysql_opts = mysql_opts.charset(&charset);
    }

    if let Some(collation) = get_string("collation", None)? {
        mysql_opts = mysql_opts.collation(&collation);
    }

    if let Some(timezone) = get_string("timezone", None)? {
        mysql_opts = mysql_opts.timezone(timezone);
    }

    if let Some(socket) = get_string("socket", None)? {
        mysql_opts = mysql_opts.socket(socket);
    }

    if let Some(port) = opts.get::<Option<u16>>(state, "port")? {
        mysql_opts = mysql_opts.port(port);
    }

    if let Some(capacity) = opts.get::<Option<usize>>(state, "statement_cache_capacity")? {
        mysql_opts = mysql_opts.statement_cache_capacity(capacity);
    }

    if mysql_opts.get_database().is_none() {
        bail!("Database name is required!");
    }

    Ok(mysql_opts)
}
