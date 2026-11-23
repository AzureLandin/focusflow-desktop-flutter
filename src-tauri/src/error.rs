pub type Result<T> = std::result::Result<T, Error>;

#[derive(Debug)]
pub enum Error {
    User(&'static str),
    Sql(rusqlite::Error),
    Io(std::io::Error),
    Json(serde_json::Error),
}

impl From<rusqlite::Error> for Error {
    fn from(error: rusqlite::Error) -> Self {
        Self::Sql(error)
    }
}
impl From<std::io::Error> for Error {
    fn from(error: std::io::Error) -> Self {
        Self::Io(error)
    }
}
impl From<serde_json::Error> for Error {
    fn from(error: serde_json::Error) -> Self {
        Self::Json(error)
    }
}

impl Error {
    pub fn message(&self) -> &'static str {
        use rusqlite::ErrorCode;
        match self {
            Self::User(message) => message,
            Self::Sql(error) => {
                eprintln!("FocusFlow database: {error}");
                match error.sqlite_error_code() {
                    Some(ErrorCode::DatabaseBusy | ErrorCode::DatabaseLocked) => {
                        "数据正在使用。请退出其他 FocusFlow 版本后重试。"
                    }
                    Some(ErrorCode::DatabaseCorrupt | ErrorCode::NotADatabase) => {
                        "数据库读取失败。请保留原文件并核对备份。"
                    }
                    _ => "数据库操作失败。请检查数据目录权限和磁盘空间后重试。",
                }
            }
            Self::Io(error) => {
                eprintln!("FocusFlow file operation: {error}");
                "无法读写本地文件。请检查目录权限和磁盘空间。"
            }
            Self::Json(error) => {
                eprintln!("FocusFlow data encoding: {error}");
                "本地数据格式有误。请核对备份后重试。"
            }
        }
    }

    pub fn ipc(self) -> String {
        format!("FF:{}", self.message())
    }
}
