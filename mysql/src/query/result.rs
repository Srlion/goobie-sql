use anyhow::{Result, bail};
use gmodx::lua::{self, ToLua};
use sqlx::{
    Column, Row, TypeInfo, ValueRef as _,
    mysql::{MySqlQueryResult, MySqlRow},
    types::{
        Decimal,
        chrono::{DateTime, NaiveDate, NaiveDateTime, NaiveTime, Utc},
    },
};

#[derive(Debug)]
pub enum QueryResult {
    Run,
    Execute(MySqlQueryResult),
    Rows(Result<Vec<Vec<ColumnValue>>>),
    Row(Result<Option<Vec<ColumnValue>>>),
}

#[derive(Debug)]
pub struct ColumnValue {
    pub column_name: String,
    pub value: Value,
}

#[derive(Debug)]
pub enum Value {
    Nil,
    Bool(bool),
    I8(i8),
    I16(i16),
    I32(i32),
    I64(i64),
    F32(f32),
    F64(f64),
    U8(u8),
    U16(u16),
    U32(u32),
    U64(u64),
    String(lua::String),
}

impl ToLua for &Value {
    fn push_to_stack(self, state: &lua::State) {
        match self {
            Value::Nil => ().push_to_stack(state),
            Value::Bool(b) => b.push_to_stack(state),
            Value::I8(i) => i.push_to_stack(state),
            Value::I16(i) => i.push_to_stack(state),
            Value::I32(i) => i.push_to_stack(state),
            Value::I64(i) => i.push_to_stack(state),
            Value::F32(f) => f.push_to_stack(state),
            Value::F64(f) => f.push_to_stack(state),
            Value::U8(u) => u.push_to_stack(state),
            Value::U16(u) => u.push_to_stack(state),
            Value::U32(u) => u.push_to_stack(state),
            Value::U64(u) => u.push_to_stack(state),
            Value::String(s) => s.push_to_stack(state),
        }
    }
}

pub fn convert_rows(rows: &[MySqlRow]) -> Result<Vec<Vec<ColumnValue>>> {
    rows.iter().map(row_to_values).collect()
}

pub fn convert_row(row: &Option<MySqlRow>) -> Result<Option<Vec<ColumnValue>>> {
    row.as_ref().map(row_to_values).transpose()
}

fn row_to_values(row: &MySqlRow) -> Result<Vec<ColumnValue>> {
    let mut values = Vec::with_capacity(row.columns().len());

    for column in row.columns() {
        let name = column.name();
        let col_type = column.type_info().name();
        let value = extract_column_value(row, name, col_type)?;

        values.push(ColumnValue {
            column_name: name.to_string(),
            value,
        });
    }

    Ok(values)
}

fn extract_column_value(row: &MySqlRow, column_name: &str, column_type: &str) -> Result<Value> {
    let raw_value = row.try_get_raw(column_name)?;
    if raw_value.is_null() {
        return Ok(Value::Nil);
    }

    let value = match column_type {
        "NULL" => Value::Nil,
        "BOOLEAN" | "BOOL" => Value::Bool(row.get(column_name)),
        "TINYINT" => Value::I8(row.get(column_name)),
        "SMALLINT" => Value::I16(row.get(column_name)),
        "INT" | "INTEGER" | "MEDIUMINT" => Value::I32(row.get(column_name)),
        "BIGINT" => Value::I64(row.get(column_name)),
        "TINYINT UNSIGNED" => Value::U8(row.get(column_name)),
        "SMALLINT UNSIGNED" => Value::U16(row.get(column_name)),
        "INT UNSIGNED" | "MEDIUMINT UNSIGNED" => Value::U32(row.get(column_name)),
        "BIGINT UNSIGNED" => Value::U64(row.get(column_name)),
        "FLOAT" => Value::F32(row.get(column_name)),
        "DOUBLE" | "REAL" => Value::F64(row.get(column_name)),
        "DECIMAL" => {
            let decimal: Decimal = row.get(column_name);
            Value::String(decimal.to_string().into())
        }
        "TIME" => {
            let time: NaiveTime = row.get(column_name);
            Value::String(time.to_string().into())
        }
        "DATE" => {
            let date: NaiveDate = row.get(column_name);
            Value::String(date.to_string().into())
        }
        "DATETIME" => {
            let datetime: NaiveDateTime = row.get(column_name);
            Value::String(datetime.to_string().into())
        }
        "TIMESTAMP" => {
            let timestamp: DateTime<Utc> = row.get(column_name);
            Value::String(timestamp.to_string().into())
        }
        "YEAR" => Value::I32(row.get(column_name)),
        "BINARY" | "VARBINARY" | "TINYBLOB" | "BLOB" | "MEDIUMBLOB" | "LONGBLOB" | "CHAR"
        | "VARCHAR" | "TEXT" | "TINYTEXT" | "MEDIUMTEXT" | "LONGTEXT" | "JSON" | "ENUM" | "SET" => {
            let binary: Vec<u8> = row.get(column_name);
            Value::String(binary.into())
        }
        "BIT" => {
            bail!(
                "BIT type is not supported, if you need it, please open an issue explaining how it should be handled"
            );
        }
        _ => {
            bail!("unsupported column type: {}", column_type);
        }
    };

    Ok(value)
}
