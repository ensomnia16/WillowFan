use std::env;
use std::error::Error;
use std::fmt;
use std::fs;
use std::path::{Path, PathBuf};
use crate::control::FanCurve;

pub const DEFAULT_TARGET_TEMP: f64 = 60.0;
pub const MIN_TARGET_TEMP: f64 = 50.0;
pub const MAX_TARGET_TEMP: f64 = 70.0;

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Config {
    pub target_temp: f64,
    pub enabled: bool,
    pub curve: FanCurve,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            target_temp: DEFAULT_TARGET_TEMP,
            enabled: false,
            curve: FanCurve::Active,
        }
    }
}

#[derive(Debug)]
pub struct ConfigError(String);

impl ConfigError {
    fn new(message: impl Into<String>) -> Self {
        Self(message.into())
    }
}

impl fmt::Display for ConfigError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(&self.0)
    }
}

impl Error for ConfigError {}

#[derive(Debug)]
pub struct DaemonConfigLoad {
    pub config: Config,
    pub warning: Option<String>,
}

pub fn default_path() -> Result<PathBuf, ConfigError> {
    let home = env::var_os("HOME")
        .filter(|value| !value.is_empty())
        .ok_or_else(|| ConfigError::new("HOME is not set; cannot locate macfan config"))?;
    Ok(PathBuf::from(home)
        .join("Library")
        .join("Application Support")
        .join("WillowFan")
        .join("config.toml"))
}

pub fn load_or_create(path: &Path) -> Result<Config, ConfigError> {
    if !path.exists() {
        write(path, Config::default())?;
    }
    let contents = fs::read_to_string(path)
        .map_err(|error| ConfigError::new(format!("failed to read {}: {error}", path.display())))?;
    parse(&contents)
        .map_err(|error| ConfigError::new(format!("failed to parse {}: {error}", path.display())))
}

pub fn load_for_daemon(path: &Path) -> DaemonConfigLoad {
    match fs::read_to_string(path) {
        Ok(contents) => match parse(&contents) {
            Ok(mut config) => {
                let requested = config.target_temp;
                config.target_temp = requested.clamp(MIN_TARGET_TEMP, MAX_TARGET_TEMP);
                let warning = (requested != config.target_temp).then(|| {
                    format!(
                        "target_temp {requested} is outside [{MIN_TARGET_TEMP}, {MAX_TARGET_TEMP}]; clamped to {}",
                        config.target_temp
                    )
                });
                DaemonConfigLoad { config, warning }
            }
            Err(error) => DaemonConfigLoad {
                config: Config::default(),
                warning: Some(format!(
                    "failed to parse {} ({error}); using target_temp={DEFAULT_TARGET_TEMP}, enabled=false",
                    path.display()
                )),
            },
        },
        Err(error) => DaemonConfigLoad {
            config: Config::default(),
            warning: Some(format!(
                "failed to read {} ({error}); using target_temp={DEFAULT_TARGET_TEMP}, enabled=false",
                path.display()
            )),
        },
    }
}

pub fn write(path: &Path, config: Config) -> Result<(), ConfigError> {
    if !config.target_temp.is_finite() {
        return Err(ConfigError::new("target_temp must be a finite number"));
    }

    let parent = path.parent().ok_or_else(|| {
        ConfigError::new(format!(
            "config path {} has no parent directory",
            path.display()
        ))
    })?;
    fs::create_dir_all(parent).map_err(|error| {
        ConfigError::new(format!(
            "failed to create config directory {}: {error}",
            parent.display()
        ))
    })?;

    let file_name = path
        .file_name()
        .and_then(|value| value.to_str())
        .unwrap_or("config.toml");
    let temporary = parent.join(format!(".{file_name}.tmp-{}", std::process::id()));
    let contents = format!(
        "target_temp = {}\nenabled = {}\ncurve = {}\n",
        format_temperature(config.target_temp),
        config.enabled,
        config.curve.name()
    );
    fs::write(&temporary, contents).map_err(|error| {
        ConfigError::new(format!(
            "failed to write temporary config {}: {error}",
            temporary.display()
        ))
    })?;
    fs::rename(&temporary, path).map_err(|error| {
        let _ = fs::remove_file(&temporary);
        ConfigError::new(format!(
            "failed to replace config {} atomically: {error}",
            path.display()
        ))
    })?;
    Ok(())
}

fn parse(contents: &str) -> Result<Config, ConfigError> {
    let mut target_temp = None;
    let mut enabled = None;
    let mut curve = None;

    for (index, raw_line) in contents.lines().enumerate() {
        let line = raw_line.split('#').next().unwrap_or_default().trim();
        if line.is_empty() {
            continue;
        }
        let Some((raw_key, raw_value)) = line.split_once('=') else {
            let apparent_key = line.split_whitespace().next().unwrap_or_default();
            if apparent_key == "target_temp" || apparent_key == "enabled" || apparent_key == "curve" {
                return Err(ConfigError::new(format!(
                    "line {} is missing '='",
                    index + 1
                )));
            }
            continue;
        };
        let key = raw_key.trim();
        let value = raw_value.trim();
        match key {
            "target_temp" => {
                let parsed = value.parse::<f64>().map_err(|_| {
                    ConfigError::new(format!(
                        "line {} has invalid target_temp '{value}'",
                        index + 1
                    ))
                })?;
                if !parsed.is_finite() {
                    return Err(ConfigError::new(format!(
                        "line {} target_temp must be finite",
                        index + 1
                    )));
                }
                target_temp = Some(parsed);
            }
            "enabled" => {
                enabled = Some(value.parse::<bool>().map_err(|_| {
                    ConfigError::new(format!(
                        "line {} has invalid enabled '{value}'; expected true or false",
                        index + 1
                    ))
                })?);
            }
            "curve" => {
                curve = Some(FanCurve::from_name(value).ok_or_else(|| {
                    ConfigError::new(format!("line {} has invalid curve '{value}'", index + 1))
                })?);
            }
            _ => {}
        }
    }

    Ok(Config {
        target_temp: target_temp
            .ok_or_else(|| ConfigError::new("missing required key target_temp"))?,
        enabled: enabled.ok_or_else(|| ConfigError::new("missing required key enabled"))?,
        curve: curve.unwrap_or(FanCurve::Active),
    })
}

fn format_temperature(value: f64) -> String {
    if value.fract() == 0.0 {
        format!("{value:.1}")
    } else {
        value.to_string()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{SystemTime, UNIX_EPOCH};

    #[test]
    fn parses_known_keys_and_ignores_unknown_lines() {
        let config = parse(
            "# comment\nunknown = value\ntarget_temp = 64.5 # warm\nenabled = false\nnoise\nenabled_extra\n",
        )
        .unwrap();

        assert_eq!(
            config,
            Config {
                target_temp: 64.5,
                enabled: false,
                curve: FanCurve::Active,
            }
        );
    }

    #[test]
    fn daemon_bad_input_falls_back_to_safe_defaults() {
        let directory = unique_test_directory();
        fs::create_dir_all(&directory).unwrap();
        let path = directory.join("config.toml");
        fs::write(&path, "target_temp = hot\nenabled = false\n").unwrap();

        let loaded = load_for_daemon(&path);

        assert_eq!(loaded.config, Config::default());
        assert!(loaded.warning.unwrap().contains("failed to parse"));
        fs::remove_dir_all(directory).unwrap();
    }

    #[test]
    fn daemon_clamps_parsed_target() {
        let directory = unique_test_directory();
        fs::create_dir_all(&directory).unwrap();
        let path = directory.join("config.toml");
        fs::write(&path, "target_temp = 100\nenabled = false\n").unwrap();

        let loaded = load_for_daemon(&path);

        assert_eq!(loaded.config.target_temp, MAX_TARGET_TEMP);
        assert!(!loaded.config.enabled);
        assert!(loaded.warning.unwrap().contains("clamped"));
        fs::remove_dir_all(directory).unwrap();
    }

    fn unique_test_directory() -> PathBuf {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        env::temp_dir().join(format!("macfan-config-test-{}-{nanos}", std::process::id()))
    }
}
