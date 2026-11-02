use crate::config;
use crate::control::{WAKE_GAP, curve_fraction, outside_deadband, slew_limited};
use crate::smc::{FanMode, FanStats, SmcClient};
use std::error::Error;
use std::fmt;
use std::fs;
use std::path::Path;
use std::process::Command;
use std::sync::atomic::{AtomicBool, Ordering};
use std::thread;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

const TICK: Duration = Duration::from_secs(2);
const POWER_CACHE: Duration = Duration::from_secs(30);
const STATUS_INTERVAL: Duration = Duration::from_secs(30);
const MAX_SENSOR_FAILURES: u8 = 3;
const HEARTBEAT_TIMEOUT: Duration = Duration::from_secs(18);

const SIGINT: i32 = 2;
const SIGTERM: i32 = 15;
const SIG_ERR: usize = usize::MAX;

static KEEP_RUNNING: AtomicBool = AtomicBool::new(true);

unsafe extern "C" {
    fn signal(signum: i32, handler: usize) -> usize;
}

#[derive(Debug)]
struct DaemonError(String);

impl DaemonError {
    fn new(message: impl Into<String>) -> Self {
        Self(message.into())
    }
}

impl fmt::Display for DaemonError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(&self.0)
    }
}

impl Error for DaemonError {}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum PowerSource {
    Ac,
    Battery,
    Unknown,
}

impl fmt::Display for PowerSource {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Ac => formatter.write_str("AC Power"),
            Self::Battery => formatter.write_str("Battery Power"),
            Self::Unknown => formatter.write_str("unknown"),
        }
    }
}

#[derive(Debug)]
struct PowerMonitor {
    source: PowerSource,
    last_checked: Option<Instant>,
}

impl PowerMonitor {
    fn new() -> Self {
        Self {
            source: PowerSource::Unknown,
            last_checked: None,
        }
    }

    fn refresh(&mut self, now: Instant) -> PowerSource {
        if self
            .last_checked
            .is_some_and(|last| now.saturating_duration_since(last) < POWER_CACHE)
        {
            return self.source;
        }
        self.last_checked = Some(now);

        match detect_power_source() {
            Ok(source) => {
                if source != self.source {
                    if self.source == PowerSource::Unknown {
                        log_event(format!("power source detected: {source}"));
                    } else {
                        log_event(format!(
                            "power source switched: {} -> {source}; effective target will change",
                            self.source
                        ));
                    }
                    self.source = source;
                }
            }
            Err(error) => log_event(format!(
                "power source check failed: {error}; keeping cached source {}",
                self.source
            )),
        }
        self.source
    }
}

#[derive(Debug)]
struct FanControlState {
    last_written_rpm: f64,
    reported_target_rpm: f64,
    needs_takeover: bool,
}

#[derive(Debug)]
struct ConfigWatcher<'a> {
    path: &'a Path,
    observed_mtime: Option<SystemTime>,
}

impl<'a> ConfigWatcher<'a> {
    fn new(path: &'a Path) -> Self {
        Self {
            path,
            observed_mtime: modified_time(path),
        }
    }

    fn reload_if_changed(&mut self) -> Option<config::DaemonConfigLoad> {
        let current_mtime = modified_time(self.path);
        if current_mtime == self.observed_mtime {
            return None;
        }
        self.observed_mtime = current_mtime;
        Some(config::load_for_daemon(self.path))
    }
}

pub fn run(config_path: &Path) -> Result<(), Box<dyn Error>> {
    if !config_path.is_absolute() {
        return Err(DaemonError::new(format!(
            "daemon config path must be absolute: {}",
            config_path.display()
        ))
        .into());
    }

    install_runtime_safety()?;
    let client = SmcClient::open()?;
    let loop_result = control_loop(&client, config_path);
    let cleanup_result = restore_auto_logged(&client, "daemon exit safety cleanup");

    match (loop_result, cleanup_result) {
        (Ok(()), Ok(())) => Ok(()),
        (Err(error), Ok(())) | (Ok(()), Err(error)) => Err(error.into()),
        (Err(loop_error), Err(cleanup_error)) => Err(DaemonError::new(format!(
            "{loop_error}; additionally, exit cleanup failed: {cleanup_error}"
        ))
        .into()),
    }
}

fn control_loop(client: &SmcClient, config_path: &Path) -> Result<(), DaemonError> {
    let loaded = config::load_for_daemon(config_path);
    if let Some(warning) = &loaded.warning {
        log_event(format!("config fallback/boundary: {warning}"));
    }
    let mut current_config = loaded.config;
    log_event(format!(
        "daemon started: config={} target_temp={:.2} curve={} enabled={} tick={}s",
        config_path.display(),
        current_config.target_temp,
        current_config.curve.name(),
        current_config.enabled,
        TICK.as_secs()
    ));

    let mut watcher = ConfigWatcher::new(config_path);
    let mut power_monitor = PowerMonitor::new();
    let mut fan_states = Vec::<FanControlState>::new();
    let mut sensor_failures = 0_u8;
    let mut auto_restored_while_disabled = false;
    let heartbeat_path = config_path.with_file_name("heartbeat");
    let started = Instant::now();
    let mut previous_tick = started;
    let mut first_tick = true;
    let mut next_status = started + STATUS_INTERVAL;

    while KEEP_RUNNING.load(Ordering::SeqCst) {
        let tick_started = Instant::now();
        let gap = if first_tick {
            Duration::ZERO
        } else {
            tick_started.saturating_duration_since(previous_tick)
        };
        first_tick = false;
        previous_tick = tick_started;

        if gap > WAKE_GAP {
            fan_states.clear();
            log_event(format!(
                "wake detected after {:.2}s gap; fan targets will resume from actual RPM",
                gap.as_secs_f64()
            ));
        }

        if let Some(reloaded) = watcher.reload_if_changed() {
            let old = current_config;
            if let Some(warning) = &reloaded.warning {
                log_event(format!("config fallback/boundary: {warning}"));
            }
            current_config = reloaded.config;
            log_event(format!(
                "config reloaded: base {:.2} -> {:.2}, curve {} -> {}, enabled {} -> {}",
                old.target_temp, current_config.target_temp,
                old.curve.name(), current_config.curve.name(), old.enabled, current_config.enabled
            ));

            if old.enabled != current_config.enabled {
                sensor_failures = 0;
                fan_states.clear();
                if current_config.enabled {
                    auto_restored_while_disabled = false;
                    log_event(
                        "control switched on by config; taking over smoothly from current RPM",
                    );
                } else {
                    log_event("control switched off by config; restoring all fans to auto");
                }
            }
        }

        let heartbeat_fresh = fs::metadata(&heartbeat_path)
            .and_then(|metadata| metadata.modified())
            .ok()
            .and_then(|modified| SystemTime::now().duration_since(modified).ok())
            .is_some_and(|age| age <= HEARTBEAT_TIMEOUT);

        if !current_config.enabled || !heartbeat_fresh {
            if !auto_restored_while_disabled {
                restore_auto_logged(client, "control disabled or app heartbeat expired")?;
                auto_restored_while_disabled = true;
            }
            if tick_started >= next_status {
                log_event(format!(
                    "status: enabled={} heartbeat={} state=standby fans=auto config_target={:.2}",
                    current_config.enabled,
                    heartbeat_fresh,
                    current_config.target_temp
                ));
                next_status = tick_started + STATUS_INTERVAL;
            }
            sleep_for_tick_remainder(tick_started);
            continue;
        }
        auto_restored_while_disabled = false;

        let hottest = match read_hottest_temperature(client) {
            Ok(hottest) => {
                if sensor_failures > 0 {
                    log_event(format!(
                        "temperature sensors recovered after {sensor_failures} consecutive failure(s)"
                    ));
                }
                sensor_failures = 0;
                hottest
            }
            Err(error) => {
                sensor_failures += 1;
                log_event(format!(
                    "temperature read failed ({sensor_failures}/{MAX_SENSOR_FAILURES}): {error}"
                ));
                if sensor_failures >= MAX_SENSOR_FAILURES {
                    return Err(DaemonError::new(format!(
                        "temperature read failed {sensor_failures} consecutive times; exiting for supervisor restart"
                    )));
                }
                sleep_for_tick_remainder(tick_started);
                continue;
            }
        };

        let power_source = power_monitor.refresh(tick_started);
        let effective_target = match power_source {
            PowerSource::Battery => (current_config.target_temp + 5.0).min(90.0),
            PowerSource::Ac | PowerSource::Unknown => current_config.target_temp,
        };
        let error = hottest.celsius - effective_target;
        let output = curve_fraction(current_config.curve, hottest.celsius, effective_target);

        let mut fan_stats = read_all_fan_stats(client)?;
        if fan_states.len() != fan_stats.len() {
            fan_states = fan_stats
                .iter()
                .map(|fan| FanControlState {
                    last_written_rpm: fan.current_rpm,
                    reported_target_rpm: fan.target_rpm,
                    needs_takeover: true,
                })
                .collect();
            log_event(format!(
                "initialized smooth takeover for {} fan(s) from current actual RPM",
                fan_states.len()
            ));
        }

        for (fan, state) in fan_stats.iter_mut().zip(&mut fan_states) {
            if !fan.min_rpm.is_finite() || !fan.max_rpm.is_finite() || fan.min_rpm > fan.max_rpm {
                return Err(DaemonError::new(format!(
                    "fan {} reported invalid RPM range [{}, {}]",
                    fan.index, fan.min_rpm, fan.max_rpm
                )));
            }
            if matches!(fan.mode, FanMode::Auto) {
                state.needs_takeover = true;
            }
            let desired = fan.min_rpm + output * (fan.max_rpm - fan.min_rpm);
            let limited = if hottest.celsius >= 100.0 {
                fan.max_rpm
            } else {
                slew_limited(state.last_written_rpm, desired)
            };
            let should_write =
                state.needs_takeover || outside_deadband(state.last_written_rpm, limited);
            if should_write {
                let reason = if state.needs_takeover {
                    "smooth takeover / fan observed in auto mode"
                } else if limited > state.last_written_rpm {
                    "PI demand increased, guarded by +250 RPM/tick slew ceiling"
                } else {
                    "PI demand decreased, guarded by -125 RPM/tick slew ceiling"
                };
                let outcome = client.set_fan_rpm(fan.index, limited).map_err(|error| {
                    DaemonError::new(format!("failed to adjust fan {}: {error}", fan.index))
                })?;
                state.last_written_rpm = outcome.applied_rpm;
                state.reported_target_rpm = outcome.applied_rpm;
                state.needs_takeover = false;
                log_event(format!(
                    "fan {} write: requested={:.0} applied={:.0} actual={:.0} u={:.3} reason={reason}",
                    fan.index, limited, outcome.applied_rpm, fan.current_rpm, output
                ));
            }
        }

        if tick_started >= next_status {
            let fans = fan_stats
                .iter()
                .zip(&fan_states)
                .map(|(fan, state)| {
                    format!(
                        "fan{} target={:.0} actual={:.0} mode={}",
                        fan.index, state.reported_target_rpm, fan.current_rpm, fan.mode
                    )
                })
                .collect::<Vec<_>>()
                .join(", ");
            log_event(format!(
                "status: PV={:.2} hottest={} base={effective_target:.2} error={error:.2} curve={} fraction={:.3} {fans} power={power_source}",
                hottest.celsius,
                hottest.key,
                current_config.curve.name(),
                output
            ));
            next_status = tick_started + STATUS_INTERVAL;
        }

        sleep_for_tick_remainder(tick_started);
    }

    log_event("SIGINT/SIGTERM received; leaving control loop for normal auto-mode cleanup");
    Ok(())
}

#[derive(Debug)]
struct HottestTemperature {
    key: String,
    celsius: f64,
}

fn read_hottest_temperature(client: &SmcClient) -> Result<HottestTemperature, DaemonError> {
    client
        .temperatures()
        .map_err(|error| DaemonError::new(format!("SMC temperature enumeration failed: {error}")))?
        .into_iter()
        .filter(|temperature| {
            temperature.celsius.is_finite()
                && temperature.celsius > 10.0
                && temperature.celsius < 120.0
        })
        .max_by(|left, right| left.celsius.total_cmp(&right.celsius))
        .map(|temperature| HottestTemperature {
            key: temperature.key,
            celsius: temperature.celsius,
        })
        .ok_or_else(|| DaemonError::new("no valid T* flt sensor in the open interval (10, 120)"))
}

fn read_all_fan_stats(client: &SmcClient) -> Result<Vec<FanStats>, DaemonError> {
    let fan_count = client
        .fan_count()
        .map_err(|error| DaemonError::new(format!("failed to read fan count: {error}")))?;
    if fan_count == 0 {
        return Err(DaemonError::new("SMC reports zero fans"));
    }
    (0..fan_count)
        .map(|index| {
            client
                .fan_stats(index)
                .map_err(|error| DaemonError::new(format!("failed to read fan {index}: {error}")))
        })
        .collect()
}

fn detect_power_source() -> Result<PowerSource, DaemonError> {
    let output = Command::new("pmset")
        .args(["-g", "batt"])
        .output()
        .map_err(|error| DaemonError::new(format!("could not execute pmset -g batt: {error}")))?;
    if !output.status.success() {
        return Err(DaemonError::new(format!(
            "pmset -g batt exited with {}: {}",
            output.status,
            String::from_utf8_lossy(&output.stderr).trim()
        )));
    }
    let stdout = String::from_utf8_lossy(&output.stdout);
    if stdout.contains("AC Power") {
        Ok(PowerSource::Ac)
    } else if stdout.contains("Battery Power") {
        Ok(PowerSource::Battery)
    } else {
        Err(DaemonError::new(format!(
            "pmset output contained neither AC Power nor Battery Power: {}",
            stdout.trim()
        )))
    }
}

fn restore_auto_logged(client: &SmcClient, reason: &str) -> Result<(), DaemonError> {
    let failures = client.restore_auto_all().map_err(|error| {
        DaemonError::new(format!(
            "failed to enumerate fans while restoring auto: {error}"
        ))
    })?;
    if failures.is_empty() {
        log_event(format!("all fans restored to auto; reason={reason}"));
        return Ok(());
    }

    let details = failures
        .into_iter()
        .map(|(index, error)| format!("fan {index}: {error}"))
        .collect::<Vec<_>>()
        .join("; ");
    Err(DaemonError::new(format!(
        "auto-mode restoration incomplete; reason={reason}; {details}"
    )))
}

fn modified_time(path: &Path) -> Option<SystemTime> {
    fs::metadata(path)
        .and_then(|metadata| metadata.modified())
        .ok()
}

fn sleep_for_tick_remainder(tick_started: Instant) {
    let elapsed = tick_started.elapsed();
    if elapsed < TICK {
        thread::sleep(TICK - elapsed);
    }
}

fn log_event(message: impl AsRef<str>) {
    let timestamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default();
    println!(
        "[{}.{:03}] {}",
        timestamp.as_secs(),
        timestamp.subsec_millis(),
        message.as_ref()
    );
}

fn install_runtime_safety() -> Result<(), DaemonError> {
    KEEP_RUNNING.store(true, Ordering::SeqCst);
    let previous_hook = std::panic::take_hook();
    std::panic::set_hook(Box::new(move |panic_info| {
        match SmcClient::open().and_then(|client| client.restore_auto_all()) {
            Ok(failures) if failures.is_empty() => {
                eprintln!("macfan panic safety: all fans restored to auto")
            }
            Ok(failures) => {
                eprintln!(
                    "macfan panic safety: auto restore incomplete for {} fan(s)",
                    failures.len()
                );
                for (index, error) in failures {
                    eprintln!("macfan panic safety: fan {index}: {error}");
                }
            }
            Err(error) => eprintln!("macfan panic safety: failed to restore auto: {error}"),
        }
        previous_hook(panic_info);
    }));

    let (sigint_result, sigterm_result) = unsafe {
        (
            signal(SIGINT, request_shutdown as *const () as usize),
            signal(SIGTERM, request_shutdown as *const () as usize),
        )
    };
    if sigint_result == SIG_ERR || sigterm_result == SIG_ERR {
        return Err(DaemonError::new(format!(
            "failed to install shutdown handlers (SIGINT={}, SIGTERM={})",
            sigint_result != SIG_ERR,
            sigterm_result != SIG_ERR
        )));
    }
    Ok(())
}

extern "C" fn request_shutdown(_signal: i32) {
    KEEP_RUNNING.store(false, Ordering::SeqCst);
}
