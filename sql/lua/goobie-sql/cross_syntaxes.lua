return {
    sqlite = {
        CROSS_NOW = "(CAST(strftime('%s', 'now') AS INTEGER))",
        -- INTEGER PRIMARY KEY auto increments in SQLite, see https://www.sqlite.org/autoinc.html
        CROSS_PRIMARY_AUTO_INCREMENTED = "INTEGER PRIMARY KEY",
        CROSS_COLLATE_BINARY = "COLLATE BINARY",
        CROSS_CURRENT_DATE = "DATE('now')",
        CROSS_OS_TIME_TYPE = "INT UNSIGNED NOT NULL DEFAULT (CAST(strftime('%s', 'now') AS INTEGER))",
        CROSS_INT_TYPE = "INTEGER",
        CROSS_JSON_TYPE = "TEXT",
    },
    mysql = {
        CROSS_NOW = "(UNIX_TIMESTAMP())",
        CROSS_PRIMARY_AUTO_INCREMENTED = "BIGINT AUTO_INCREMENT PRIMARY KEY",
        CROSS_COLLATE_BINARY = "BINARY",
        CROSS_CURRENT_DATE = "CURDATE()",
        CROSS_OS_TIME_TYPE = "INT UNSIGNED NOT NULL DEFAULT (UNIX_TIMESTAMP())",
        CROSS_INT_TYPE = "BIGINT",
        CROSS_JSON_TYPE = "JSON",
    },
}
