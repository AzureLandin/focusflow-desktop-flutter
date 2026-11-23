pub mod backup;
pub mod db;
pub mod error;
pub mod model;
pub mod pomodoro;
pub mod repository;

use error::{Error, Result};
use model::{Command, Pulse, Query, Workspace};
use repository::{Repository, TimerEvent};
use std::{
    path::PathBuf,
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc, Mutex,
    },
    time::Duration,
};
use tauri::{AppHandle, Emitter, Manager, RunEvent, WebviewWindow, WebviewWindowBuilder};
use tauri_plugin_dialog::{DialogExt, MessageDialogButtons, MessageDialogKind};
use tauri_plugin_notification::NotificationExt;

type Reply<T> = std::result::Result<T, String>;

struct AppState {
    repository: Mutex<Option<Repository>>,
    running: Arc<AtomicBool>,
}

fn data_path(app: &AppHandle) -> Result<PathBuf> {
    let override_path = std::env::var_os("FOCUSFLOW_DATA_DIR")
        .map(PathBuf::from)
        .or_else(|| {
            std::env::args().find_map(|arg| arg.strip_prefix("--user-data-dir=").map(PathBuf::from))
        });
    let folder = if let Some(path) = override_path {
        if !path.is_absolute() {
            return Err(Error::User("自定义数据目录必须为绝对路径。"));
        }
        path
    } else {
        let base = app
            .path()
            .data_dir()
            .map_err(|_| Error::User("无法定位系统数据目录。"))?;
        base.join(if cfg!(debug_assertions) {
            "FocusFlow Development"
        } else {
            "FocusFlow"
        })
    };
    Ok(folder.join("focusflow.sqlite3"))
}

fn timer_event(app: &AppHandle, event: TimerEvent) {
    if event.sound {
        if let Some(window) = app
            .get_webview_window("main")
            .filter(|window| window.is_visible().unwrap_or(false))
        {
            if let Err(error) = window.emit("timer-chime", ()) {
                eprintln!("FocusFlow chime: {error}");
            }
        }
    }
    if event.notify {
        if let Err(error) = app
            .notification()
            .builder()
            .title("FocusFlow")
            .body(event.message)
            .show()
        {
            eprintln!("FocusFlow system notification: {error}");
        }
    }
}

fn with_repository<T>(
    app: &AppHandle,
    operation: impl FnOnce(&mut Repository, i64) -> Result<T>,
) -> Result<T> {
    let state = app
        .try_state::<AppState>()
        .ok_or(Error::User("本地数据还未准备好。"))?;
    let mut guard = state
        .repository
        .lock()
        .map_err(|_| Error::User("数据库暂时无法访问，请重启 FocusFlow。"))?;
    let repository = guard.as_mut().ok_or(Error::User("应用正在退出。"))?;
    let now = model::now();
    let event = repository.sync(now)?;
    let result = operation(repository, now);
    drop(guard);
    if let Some(event) = event {
        timer_event(app, event);
    }
    result
}

fn from_main(window: &WebviewWindow) -> Reply<()> {
    if window.label() == "main" {
        Ok(())
    } else {
        Err(Error::User("无法验证操作来源。").ipc())
    }
}

fn input<T: serde::de::DeserializeOwned>(value: serde_json::Value) -> Reply<T> {
    serde_json::from_value(value)
        .map_err(|_| Error::User("输入格式或数值超出允许范围，请检查后重试。").ipc())
}

#[tauri::command]
fn workspace_read(
    window: WebviewWindow,
    app: AppHandle,
    query: serde_json::Value,
) -> Reply<Workspace> {
    from_main(&window)?;
    let query: Query = input(query)?;
    with_repository(&app, |repo, now| repo.read(query, now)).map_err(Error::ipc)
}

#[tauri::command]
fn workspace_pulse(window: WebviewWindow, app: AppHandle) -> Reply<Pulse> {
    from_main(&window)?;
    with_repository(&app, |repo, now| repo.pulse(now)).map_err(Error::ipc)
}

#[tauri::command]
fn workspace_command(
    window: WebviewWindow,
    app: AppHandle,
    command: serde_json::Value,
) -> Reply<()> {
    from_main(&window)?;
    let command: Command = input(command)?;
    with_repository(&app, |repo, now| repo.command(command, now)).map_err(Error::ipc)
}

#[tauri::command]
async fn backup_export(window: WebviewWindow, app: AppHandle) -> Reply<bool> {
    from_main(&window)?;
    tauri::async_runtime::spawn_blocking(move || -> Result<bool> {
        with_repository(&app, |repo, _| backup::ensure_idle(repo))?;
        let chosen = app
            .dialog()
            .file()
            .set_parent(&window)
            .add_filter("JSON 备份", &["json"])
            .set_title("导出 FocusFlow 备份")
            .set_file_name("FocusFlow-backup.json")
            .blocking_save_file();
        let Some(file) = chosen else {
            return Ok(false);
        };
        let path = file
            .into_path()
            .map_err(|_| Error::User("无法读取本地文件路径。"))?;
        let snapshot = with_repository(&app, |repo, _| {
            backup::ensure_idle(repo)?;
            backup::snapshot(&repo.db)
        })?;
        backup::write_file(&path, &snapshot, true)?;
        Ok(true)
    })
    .await
    .map_err(|_| Error::User("备份导出未完成。").ipc())?
    .map_err(Error::ipc)
}

#[tauri::command]
async fn backup_restore(window: WebviewWindow, app: AppHandle) -> Reply<bool> {
    from_main(&window)?;
    tauri::async_runtime::spawn_blocking(move || -> Result<bool> {
        with_repository(&app, |repo, _| backup::ensure_idle(repo))?;
        let chosen = app
            .dialog()
            .file()
            .set_parent(&window)
            .add_filter("JSON 备份", &["json"])
            .set_title("选择 FocusFlow 备份")
            .blocking_pick_file();
        let Some(file) = chosen else {
            return Ok(false);
        };
        let path = file
            .into_path()
            .map_err(|_| Error::User("无法读取本地文件路径。"))?;
        let value = backup::read_file(&path)?;
        let approved = app
            .dialog()
            .message("用此备份替换当前应用数据？应用会先保存一份当前数据的 JSON 备份。")
            .title("恢复备份")
            .kind(MessageDialogKind::Warning)
            .buttons(MessageDialogButtons::OkCancel)
            .blocking_show();
        if !approved {
            return Ok(false);
        }
        with_repository(&app, |repo, now| backup::restore(repo, value, now))?;
        Ok(true)
    })
    .await
    .map_err(|_| Error::User("备份恢复未完成。").ipc())?
    .map_err(Error::ipc)
}

fn show_main(app: &AppHandle) {
    if let Some(window) = app.get_webview_window("main") {
        let _ = window.show();
        let _ = window.unminimize();
        let _ = window.set_focus();
    }
}

fn start(app: &AppHandle) -> Result<()> {
    let mut repository = Repository::open(&data_path(app)?)?;
    let first_event = repository.sync(model::now())?;
    let running = Arc::new(AtomicBool::new(true));
    app.manage(AppState {
        repository: Mutex::new(Some(repository)),
        running: running.clone(),
    });

    let config = &app.config().app.windows[0];
    let dev_origin = app.config().build.dev_url.as_ref().map(|url| url.origin());
    WebviewWindowBuilder::from_config(app, config)
        .map_err(|_| Error::User("无法配置 FocusFlow 窗口。"))?
        .on_navigation(move |url| {
            let local = matches!(
                (url.scheme(), url.host_str()),
                ("tauri", Some("localhost")) | ("http" | "https", Some("tauri.localhost"))
            );
            local
                || (cfg!(debug_assertions)
                    && dev_origin
                        .as_ref()
                        .is_some_and(|origin| *origin == url.origin()))
        })
        .on_new_window(|_, _| tauri::webview::NewWindowResponse::Deny)
        .build()
        .map_err(|error| {
            eprintln!("FocusFlow window: {error}");
            Error::User("无法创建 FocusFlow 窗口。")
        })?;
    show_main(app);
    if let Some(event) = first_event {
        timer_event(app, event);
    }
    let app = app.clone();
    std::thread::spawn(move || {
        let mut failed = false;
        while running.load(Ordering::Acquire) {
            std::thread::sleep(Duration::from_millis(750));
            if !running.load(Ordering::Acquire) {
                break;
            }
            match with_repository(&app, |_, _| Ok(())) {
                Ok(()) => failed = false,
                Err(error) if !failed => {
                    let _ = error.message();
                    failed = true;
                }
                Err(_) => {}
            }
        }
    });
    Ok(())
}

pub fn run() {
    let application = tauri::Builder::default()
        .plugin(tauri_plugin_single_instance::init(|app, _, _| {
            show_main(app)
        }))
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_notification::init())
        .invoke_handler(tauri::generate_handler![
            workspace_read,
            workspace_pulse,
            workspace_command,
            backup_export,
            backup_restore
        ])
        .setup(|app| {
            if let Err(error) = start(app.handle()) {
                let handle = app.handle().clone();
                app.dialog()
                    .message(error.message())
                    .title("FocusFlow 无法启动")
                    .kind(MessageDialogKind::Error)
                    .show(move |_| handle.exit(1));
            }
            Ok(())
        })
        .on_window_event(|window, event| {
            if window.label() != "main" {
                return;
            }
            match event {
                tauri::WindowEvent::Focused(true) => {
                    let _ = with_repository(window.app_handle(), |_, _| Ok(()));
                }
                #[cfg(target_os = "macos")]
                tauri::WindowEvent::CloseRequested { api, .. } => {
                    api.prevent_close();
                    let _ = window.hide();
                }
                #[cfg(target_os = "windows")]
                tauri::WindowEvent::Destroyed => window.app_handle().exit(0),
                _ => {}
            }
        })
        .build(tauri::generate_context!());

    match application {
        Ok(application) => application.run(|app, event| match event {
            #[cfg(target_os = "macos")]
            RunEvent::Reopen {
                has_visible_windows: false,
                ..
            } => show_main(app),
            RunEvent::Exit => {
                if let Some(state) = app.try_state::<AppState>() {
                    state.running.store(false, Ordering::Release);
                    if let Ok(mut repository) = state.repository.lock() {
                        repository.take();
                    }
                }
            }
            _ => {}
        }),
        Err(error) => eprintln!("FocusFlow initialization: {error}"),
    }
}
