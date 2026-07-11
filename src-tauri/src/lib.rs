use std::os::unix::net::UnixStream;
use std::io::{Read, Write};
use serde_json::json;

#[tauri::command]
fn get_agent_status() -> Result<serde_json::Value, String> {
    let socket_path = "/var/run/kinnector/control.sock";
    let mut stream = UnixStream::connect(socket_path).map_err(|e| format!("Failed to connect to control socket: {}", e))?;
    
    let req = json!({
        "type": "Status",
        "payload": null
    });
    
    let req_bytes = serde_json::to_vec(&req).map_err(|e| e.to_string())?;
    stream.write_all(&req_bytes).map_err(|e| e.to_string())?;
    stream.shutdown(std::net::Shutdown::Write).map_err(|e| e.to_string())?;
    
    let mut resp_bytes = Vec::new();
    stream.read_to_end(&mut resp_bytes).map_err(|e| e.to_string())?;
    
    let resp: serde_json::Value = serde_json::from_slice(&resp_bytes).map_err(|e| e.to_string())?;
    Ok(resp)
}

#[tauri::command]
fn reload_agent_rules() -> Result<serde_json::Value, String> {
    let socket_path = "/var/run/kinnector/control.sock";
    let mut stream = UnixStream::connect(socket_path).map_err(|e| format!("Failed to connect: {}", e))?;
    
    let req = json!({
        "type": "ReloadRules",
        "payload": null
    });
    
    let req_bytes = serde_json::to_vec(&req).map_err(|e| e.to_string())?;
    stream.write_all(&req_bytes).map_err(|e| e.to_string())?;
    stream.shutdown(std::net::Shutdown::Write).map_err(|e| e.to_string())?;
    
    let mut resp_bytes = Vec::new();
    stream.read_to_end(&mut resp_bytes).map_err(|e| e.to_string())?;
    
    let resp: serde_json::Value = serde_json::from_slice(&resp_bytes).map_err(|e| e.to_string())?;
    Ok(resp)
}

#[tauri::command]
fn release_containment(pid: u32) -> Result<serde_json::Value, String> {
    let socket_path = "/var/run/kinnector/control.sock";
    let mut stream = UnixStream::connect(socket_path).map_err(|e| format!("Failed to connect: {}", e))?;
    
    let req = json!({
        "type": "ReleaseContainment",
        "payload": pid
    });
    
    let req_bytes = serde_json::to_vec(&req).map_err(|e| e.to_string())?;
    stream.write_all(&req_bytes).map_err(|e| e.to_string())?;
    stream.shutdown(std::net::Shutdown::Write).map_err(|e| e.to_string())?;
    
    let mut resp_bytes = Vec::new();
    stream.read_to_end(&mut resp_bytes).map_err(|e| e.to_string())?;
    
    let resp: serde_json::Value = serde_json::from_slice(&resp_bytes).map_err(|e| e.to_string())?;
    Ok(resp)
}

#[tauri::command]
fn get_agent_logs() -> Result<String, String> {
    let log_path = "/var/log/kinnector/alerts.log";
    if !std::path::Path::new(log_path).exists() {
        return Ok("No EDR alert logs found.".to_string());
    }
    std::fs::read_to_string(log_path).map_err(|e| e.to_string())
}

use tauri::Emitter;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .invoke_handler(tauri::generate_handler![
            get_agent_status,
            reload_agent_rules,
            release_containment,
            get_agent_logs
        ])
        .setup(|app| {
            let handle = app.handle().clone();
            tauri::async_runtime::spawn(async move {
                loop {
                    match tokio::net::UnixStream::connect("/var/run/kinnector/control.sock").await {
                        Ok(mut stream) => {
                            let req = json!({
                                "type": "Subscribe",
                                "payload": null
                            });
                            if let Ok(req_bytes) = serde_json::to_vec(&req) {
                                use tokio::io::AsyncWriteExt;
                                if stream.write_all(&req_bytes).await.is_ok() {
                                    let mut reader = tokio::io::BufReader::new(stream);
                                    let mut line = String::new();
                                    use tokio::io::AsyncBufReadExt;
                                    
                                    // First line is status success "Subscription active"
                                    if reader.read_line(&mut line).await.is_ok() {
                                        line.clear();
                                        
                                        // Subsequent lines are Alert JSON lines
                                        while reader.read_line(&mut line).await.is_ok() {
                                            let trimmed = line.trim();
                                            if !trimmed.is_empty() {
                                                if let Ok(alert) = serde_json::from_str::<serde_json::Value>(trimmed) {
                                                    // Emit event to Svelte frontend
                                                    let _ = handle.emit("alert", alert);
                                                }
                                            }
                                            line.clear();
                                        }
                                    }
                                }
                            }
                        }
                        Err(_) => {}
                    }
                    tokio::time::sleep(tokio::time::Duration::from_secs(2)).await;
                }
            });
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
