mod config;
mod control;
mod daemon;
mod smc;

use smc::SmcClient;
use control::FanCurve;
use std::env;
use std::error::Error;
use std::fmt;
use std::path::PathBuf;
use std::process::ExitCode;

const USAGE: &str = "Usage:\n  macfan probe\n  macfan set <fan_index> <rpm>\n  macfan auto\n  macfan daemon --config <absolute_path>\n  macfan target <°C>\n  macfan curve <quiet|balanced|active>\n  macfan on\n  macfan off\n  macfan status";

unsafe extern "C" {
    fn geteuid() -> u32;
    fn signal(signum: i32, handler: usize) -> usize;
}

// SIGPIPE default-kill instead of Rust's ignore: `macfan probe | head` must not
// panic with "failed printing to stdout: Broken pipe".
const SIGPIPE: i32 = 13;
const SIG_DFL: usize = 0;

#[derive(Debug)]
struct CliError(String);

impl fmt::Display for CliError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(&self.0)
    }
}

impl Error for CliError {}

fn main() -> ExitCode {
    unsafe {
        signal(SIGPIPE, SIG_DFL);
    }
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => {
            eprintln!("error: {error}");
            ExitCode::FAILURE
        }
    }
}

fn run() -> Result<(), Box<dyn Error>> {
    let mut arguments = env::args().skip(1);
    let Some(command) = arguments.next() else {
        return Err(CliError(USAGE.to_owned()).into());
    };

    match command.as_str() {
        "probe" => {
            ensure_no_extra_arguments(arguments)?;
            probe()
        }
        "set" => {
            let fan_index = arguments
                .next()
                .ok_or_else(|| CliError(format!("set requires <fan_index> and <rpm>\n{USAGE}")))?;
            let rpm = arguments
                .next()
                .ok_or_else(|| CliError(format!("set requires <fan_index> and <rpm>\n{USAGE}")))?;
            ensure_no_extra_arguments(arguments)?;

            let fan_index = fan_index.parse::<usize>().map_err(|_| {
                CliError(format!(
                    "invalid fan_index '{fan_index}': expected a non-negative integer"
                ))
            })?;
            let rpm = rpm
                .parse::<f64>()
                .map_err(|_| CliError(format!("invalid rpm '{rpm}': expected a number")))?;
            require_root("set")?;
            set_fan(fan_index, rpm)
        }
        "auto" => {
            ensure_no_extra_arguments(arguments)?;
            require_root("auto")?;
            restore_auto()
        }
        "daemon" => {
            let flag = arguments.next().ok_or_else(|| {
                CliError(format!("daemon requires --config <absolute_path>\n{USAGE}"))
            })?;
            if flag != "--config" {
                return Err(CliError(format!(
                    "unexpected daemon option '{flag}'; expected --config <absolute_path>\n{USAGE}"
                ))
                .into());
            }
            let path = arguments.next().ok_or_else(|| {
                CliError(format!("daemon requires --config <absolute_path>\n{USAGE}"))
            })?;
            ensure_no_extra_arguments(arguments)?;
            require_root("daemon")?;
            daemon::run(&PathBuf::from(path))
        }
        "target" => {
            let target = arguments
                .next()
                .ok_or_else(|| CliError(format!("target requires <°C>\n{USAGE}")))?;
            ensure_no_extra_arguments(arguments)?;
            let target = target.parse::<f64>().map_err(|_| {
                CliError(format!(
                    "invalid target temperature '{target}': expected a number"
                ))
            })?;
            if !target.is_finite() {
                return Err(CliError("target temperature must be finite".to_owned()).into());
            }
            update_target(target)
        }
        "curve" => {
            let name = arguments.next().ok_or_else(|| CliError("curve name is required".to_owned()))?;
            ensure_no_extra_arguments(arguments)?;
            let curve = FanCurve::from_name(&name)
                .ok_or_else(|| CliError(format!("unknown curve '{name}'")))?;
            update_curve(curve)
        }
        "on" => {
            ensure_no_extra_arguments(arguments)?;
            update_enabled(true)
        }
        "off" => {
            ensure_no_extra_arguments(arguments)?;
            update_enabled(false)
        }
        "status" => {
            ensure_no_extra_arguments(arguments)?;
            status()
        }
        _ => Err(CliError(format!("unknown command '{command}'\n{USAGE}")).into()),
    }
}

fn ensure_no_extra_arguments(mut arguments: impl Iterator<Item = String>) -> Result<(), CliError> {
    if let Some(argument) = arguments.next() {
        Err(CliError(format!(
            "unexpected argument '{argument}'\n{USAGE}"
        )))
    } else {
        Ok(())
    }
}

fn require_root(command: &str) -> Result<(), CliError> {
    if unsafe { geteuid() } == 0 {
        Ok(())
    } else {
        Err(CliError(format!(
            "'{command}' requires root privileges because it writes SMC fan controls; run it with sudo"
        )))
    }
}

fn probe() -> Result<(), Box<dyn Error>> {
    let client = SmcClient::open()?;
    let fan_count = client.fan_count()?;

    println!("Fans: {fan_count}");
    for index in 0..fan_count {
        let fan = client.fan_stats(index)?;
        println!(
            "Fan {}: current={} RPM min={} RPM max={} RPM target={} RPM mode={}",
            fan.index,
            format_rpm(fan.current_rpm),
            format_rpm(fan.min_rpm),
            format_rpm(fan.max_rpm),
            format_rpm(fan.target_rpm),
            fan.mode
        );
    }

    println!("Temperatures:");
    for temperature in client.temperatures()? {
        println!("{}: {:.2} °C", temperature.key, temperature.celsius);
    }
    Ok(())
}

fn set_fan(fan_index: usize, rpm: f64) -> Result<(), Box<dyn Error>> {
    let client = SmcClient::open()?;
    let outcome = client.set_fan_rpm(fan_index, rpm)?;
    println!(
        "Fan {fan_index} forced target set to {} RPM (requested {} RPM, allowed [{}, {}] RPM)",
        format_rpm(outcome.applied_rpm),
        format_rpm(outcome.requested_rpm),
        format_rpm(outcome.min_rpm),
        format_rpm(outcome.max_rpm)
    );
    Ok(())
}

fn restore_auto() -> Result<(), Box<dyn Error>> {
    let client = SmcClient::open()?;
    let failures = client.restore_auto_all()?;
    if failures.is_empty() {
        println!("All fans restored to automatic mode");
        return Ok(());
    }

    eprintln!(
        "failed to restore automatic mode for {} fan(s):",
        failures.len()
    );
    for (index, error) in &failures {
        eprintln!("  fan {index}: {error}");
    }
    Err(CliError("automatic mode restoration was incomplete".to_owned()).into())
}

fn update_target(target_temp: f64) -> Result<(), Box<dyn Error>> {
    let path = config::default_path()?;
    let mut current = config::load_or_create(&path)?;
    current.target_temp = target_temp.clamp(config::MIN_TARGET_TEMP, config::MAX_TARGET_TEMP);
    config::write(&path, current)?;
    println!(
        "Updated {}: target_temp={:.2}, enabled={}",
        path.display(),
        current.target_temp,
        current.enabled
    );
    Ok(())
}

fn update_curve(curve: FanCurve) -> Result<(), Box<dyn Error>> {
    let path = config::default_path()?;
    let mut current = config::load_or_create(&path)?;
    current.curve = curve;
    config::write(&path, current)?;
    println!("Selected fan curve: {}", curve.name());
    Ok(())
}

fn update_enabled(enabled: bool) -> Result<(), Box<dyn Error>> {
    let path = config::default_path()?;
    let mut current = config::load_or_create(&path)?;
    current.enabled = enabled;
    config::write(&path, current)?;
    println!(
        "Updated {}: target_temp={:.2}, enabled={}",
        path.display(),
        current.target_temp,
        current.enabled
    );
    Ok(())
}

fn status() -> Result<(), Box<dyn Error>> {
    let config_path = config::default_path()?;
    let current_config = config::load_or_create(&config_path)?;
    let client = SmcClient::open()?;
    let mut temperatures: Vec<_> = client
        .temperatures()?
        .into_iter()
        .filter(|temperature| {
            temperature.celsius.is_finite()
                && temperature.celsius > 10.0
                && temperature.celsius < 120.0
        })
        .collect();
    temperatures.sort_by(|left, right| right.celsius.total_cmp(&left.celsius));
    let hottest = temperatures.first().ok_or_else(|| {
        CliError("no valid T* flt sensor in the open interval (10, 120)".to_owned())
    })?;

    println!(
        "Hottest sensor: {} = {:.2} °C",
        hottest.key, hottest.celsius
    );
    for temperature in &temperatures {
        println!("Sensor {}: {:.2} °C", temperature.key, temperature.celsius);
    }
    let fan_count = client.fan_count()?;
    for index in 0..fan_count {
        let fan = client.fan_stats(index)?;
        println!(
            "Fan {}: current={} RPM target={} RPM min={} RPM max={} RPM mode={}",
            fan.index,
            format_rpm(fan.current_rpm),
            format_rpm(fan.target_rpm),
            format_rpm(fan.min_rpm),
            format_rpm(fan.max_rpm),
            fan.mode
        );
    }
    println!("Config: {}", config_path.display());
    println!("  target_temp = {:.2}", current_config.target_temp);
    println!("  enabled = {}", current_config.enabled);
    println!("  curve = {}", current_config.curve.name());
    Ok(())
}

fn format_rpm(value: f64) -> String {
    if value.fract().abs() < 0.005 {
        format!("{value:.0}")
    } else {
        format!("{value:.2}")
    }
}
