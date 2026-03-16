use std::path::PathBuf;

#[derive(Debug, Clone)]
pub struct AppPaths {
    pub root: PathBuf,
    pub models: PathBuf,
    pub whisper_models: PathBuf,
    pub parakeet_models: PathBuf,
    pub runtime: PathBuf,
    pub logs: PathBuf,
    pub recordings: PathBuf,
    pub settings: PathBuf,
    pub history: PathBuf,
}

impl AppPaths {
    pub fn current() -> Self {
        let root = std::env::var_os("XDG_DATA_HOME")
            .map(PathBuf::from)
            .or_else(|| {
                std::env::var_os("HOME")
                    .map(PathBuf::from)
                    .map(|home| home.join(".local").join("share"))
            })
            .unwrap_or_else(|| PathBuf::from("."))
            .join("verbatim");
        Self {
            models: root.join("Models"),
            whisper_models: root.join("Models").join("Whisper"),
            parakeet_models: root.join("Models").join("Parakeet"),
            runtime: root.join("Runtime"),
            logs: root.join("Logs"),
            recordings: root.join("Recordings"),
            settings: root.join("settings.json"),
            history: root.join("history.sqlite"),
            root,
        }
    }

    pub fn ensure_directories_exist(&self) -> std::io::Result<()> {
        std::fs::create_dir_all(&self.root)?;
        std::fs::create_dir_all(&self.models)?;
        std::fs::create_dir_all(&self.whisper_models)?;
        std::fs::create_dir_all(&self.parakeet_models)?;
        std::fs::create_dir_all(&self.runtime)?;
        std::fs::create_dir_all(&self.logs)?;
        std::fs::create_dir_all(&self.recordings)?;
        Ok(())
    }
}
