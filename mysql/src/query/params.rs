use anyhow::{Result, bail};
use gmodx::lua::{self, Table};

#[derive(Debug, Clone)]
pub enum Param {
    Number(f64),
    String(lua::String),
    Bool(bool),
}

pub fn parse_params(state: &lua::State, params: Table) -> Result<Vec<Param>> {
    let mut out = Vec::new();

    for (i, v) in params.ipairs::<lua::Value>(state) {
        use lua::ValueKind;
        let param = match v.type_kind() {
            ValueKind::Bool => Param::Bool(v.to::<bool>(state)?),
            ValueKind::Number => Param::Number(v.to::<f64>(state)?),
            ValueKind::String => Param::String(v.to::<lua::String>(state)?),
            _ => bail!("unsupported parameter type {i}: {}", v.type_name()),
        };
        out.push(param);
    }

    Ok(out)
}
