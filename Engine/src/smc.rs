use std::error::Error;
use std::ffi::{c_char, c_void};
use std::fmt;
use std::mem::size_of;

type KernReturn = i32;
type MachPort = u32;
type IoObject = MachPort;
type IoService = IoObject;
type IoConnect = MachPort;

const K_IO_MAIN_PORT_DEFAULT: MachPort = 0;
const KERN_SUCCESS: KernReturn = 0;
const SMC_SELECTOR: u32 = 2;
const SMC_READ_KEY: u8 = 5;
const SMC_WRITE_KEY: u8 = 6;
const SMC_GET_KEY_FROM_INDEX: u8 = 8;
const SMC_GET_KEY_INFO: u8 = 9;

const TYPE_FLT: u32 = u32::from_be_bytes(*b"flt ");
const TYPE_UI8: u32 = u32::from_be_bytes(*b"ui8 ");
const TYPE_UI16: u32 = u32::from_be_bytes(*b"ui16");
const TYPE_UI32: u32 = u32::from_be_bytes(*b"ui32");
const TYPE_FPE2: u32 = u32::from_be_bytes(*b"fpe2");
const TYPE_SP78: u32 = u32::from_be_bytes(*b"sp78");

#[repr(C)]
#[derive(Clone, Copy, Debug, Default)]
struct SmcKeyDataVers {
    major: u8,
    minor: u8,
    build: u8,
    reserved: [u8; 1],
    release: u16,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default)]
struct SmcKeyDataPLimitData {
    version: u16,
    length: u16,
    cpu_p_limit: u32,
    gpu_p_limit: u32,
    mem_p_limit: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default)]
struct SmcKeyDataKeyInfo {
    data_size: u32,
    data_type: u32,
    data_attributes: u8,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default)]
struct SmcKeyData {
    key: u32,
    vers: SmcKeyDataVers,
    p_limit_data: SmcKeyDataPLimitData,
    key_info: SmcKeyDataKeyInfo,
    result: u8,
    status: u8,
    data8: u8,
    data32: u32,
    bytes: [u8; 32],
}

const _: [(); 6] = [(); size_of::<SmcKeyDataVers>()];
const _: [(); 16] = [(); size_of::<SmcKeyDataPLimitData>()];
const _: [(); 12] = [(); size_of::<SmcKeyDataKeyInfo>()];
const _: [(); 80] = [(); size_of::<SmcKeyData>()];

#[link(name = "IOKit", kind = "framework")]
unsafe extern "C" {
    fn IOServiceMatching(name: *const c_char) -> *mut c_void;
    fn IOServiceGetMatchingService(main_port: MachPort, matching: *mut c_void) -> IoService;
    fn IOServiceOpen(
        service: IoService,
        owning_task: MachPort,
        r#type: u32,
        connect: *mut IoConnect,
    ) -> KernReturn;
    fn IOObjectRelease(object: IoObject) -> KernReturn;
    fn IOServiceClose(connect: IoConnect) -> KernReturn;
    fn IOConnectCallStructMethod(
        connection: IoConnect,
        selector: u32,
        input: *const c_void,
        input_size: usize,
        output: *mut c_void,
        output_size: *mut usize,
    ) -> KernReturn;
}

unsafe extern "C" {
    static mach_task_self_: MachPort;
}

#[derive(Debug)]
pub struct SmcError {
    message: String,
}

impl SmcError {
    fn new(message: impl Into<String>) -> Self {
        Self {
            message: message.into(),
        }
    }

    fn context(self, context: impl AsRef<str>) -> Self {
        Self::new(format!("{}: {}", context.as_ref(), self.message))
    }
}

impl fmt::Display for SmcError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(&self.message)
    }
}

impl Error for SmcError {}

#[derive(Clone, Copy, Debug)]
struct KeyInfo {
    data_size: u32,
    data_type: u32,
}

#[derive(Clone, Copy, Debug)]
pub enum FanMode {
    Auto,
    Forced,
    Unknown(u64),
}

impl fmt::Display for FanMode {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Auto => formatter.write_str("auto"),
            Self::Forced => formatter.write_str("forced"),
            Self::Unknown(value) => write!(formatter, "unknown({value})"),
        }
    }
}

#[derive(Debug)]
pub struct FanStats {
    pub index: usize,
    pub current_rpm: f64,
    pub min_rpm: f64,
    pub max_rpm: f64,
    pub target_rpm: f64,
    pub mode: FanMode,
}

#[derive(Debug)]
pub struct Temperature {
    pub key: String,
    pub celsius: f64,
}

#[derive(Debug)]
pub struct SetOutcome {
    pub requested_rpm: f64,
    pub applied_rpm: f64,
    pub min_rpm: f64,
    pub max_rpm: f64,
}

pub struct SmcClient {
    connection: IoConnect,
}

impl SmcClient {
    pub fn open() -> Result<Self, SmcError> {
        let matching = unsafe { IOServiceMatching(c"AppleSMC".as_ptr()) };
        if matching.is_null() {
            return Err(SmcError::new("IOServiceMatching(AppleSMC) returned null"));
        }

        let service = unsafe { IOServiceGetMatchingService(K_IO_MAIN_PORT_DEFAULT, matching) };
        if service == 0 {
            return Err(SmcError::new("AppleSMC service was not found"));
        }

        let mut connection = 0;
        let open_result = unsafe { IOServiceOpen(service, mach_task_self_, 0, &mut connection) };
        let release_result = unsafe { IOObjectRelease(service) };

        if open_result != KERN_SUCCESS {
            return Err(SmcError::new(format!(
                "IOServiceOpen(AppleSMC) failed with IOKit code {open_result:#x}"
            )));
        }
        if release_result != KERN_SUCCESS {
            unsafe {
                IOServiceClose(connection);
            }
            return Err(SmcError::new(format!(
                "IOObjectRelease(AppleSMC) failed with IOKit code {release_result:#x}"
            )));
        }

        Ok(Self { connection })
    }

    pub fn fan_count(&self) -> Result<usize, SmcError> {
        let value = self
            .read_integer(key_from_bytes(*b"FNum"))
            .map_err(|error| error.context("failed to read FNum"))?;
        usize::try_from(value)
            .map_err(|_| SmcError::new(format!("FNum value {value} does not fit usize")))
    }

    pub fn fan_stats(&self, index: usize) -> Result<FanStats, SmcError> {
        self.validate_fan_index(index)?;
        let current_rpm = self.read_fan_numeric(index, *b"Ac")?;
        let min_rpm = self.read_fan_numeric(index, *b"Mn")?;
        let max_rpm = self.read_fan_numeric(index, *b"Mx")?;
        let target_rpm = self.read_fan_numeric(index, *b"Tg")?;
        let mode = self.read_fan_mode(index)?;

        Ok(FanStats {
            index,
            current_rpm,
            min_rpm,
            max_rpm,
            target_rpm,
            mode,
        })
    }

    pub fn temperatures(&self) -> Result<Vec<Temperature>, SmcError> {
        let key_count = self
            .read_integer(key_from_bytes(*b"#KEY"))
            .map_err(|error| error.context("failed to read #KEY"))?;
        let key_count = u32::try_from(key_count)
            .map_err(|_| SmcError::new(format!("#KEY value {key_count} does not fit u32")))?;
        let mut temperatures = Vec::new();

        for index in 0..key_count {
            let Ok(key) = self.key_at_index(index) else {
                continue;
            };
            if key.to_be_bytes()[0] != b'T' {
                continue;
            }

            let Ok(info) = self.key_info(key) else {
                continue;
            };
            if info.data_type != TYPE_FLT {
                continue;
            }

            let Ok(value) = self.read_numeric_with_info(key, info) else {
                continue;
            };
            if value.is_finite() && value >= 10.0 {
                temperatures.push(Temperature {
                    key: key_name(key),
                    celsius: value,
                });
            }
        }

        Ok(temperatures)
    }

    pub fn set_fan_rpm(&self, index: usize, requested_rpm: f64) -> Result<SetOutcome, SmcError> {
        self.validate_fan_index(index)?;
        if !requested_rpm.is_finite() {
            return Err(SmcError::new("requested RPM must be a finite number"));
        }

        let min_rpm = self.read_fan_numeric(index, *b"Mn")?;
        let max_rpm = self.read_fan_numeric(index, *b"Mx")?;
        if !min_rpm.is_finite() || !max_rpm.is_finite() || min_rpm > max_rpm {
            return Err(SmcError::new(format!(
                "fan {index} reported invalid RPM range [{min_rpm}, {max_rpm}]"
            )));
        }

        // Forced mode MUST be engaged before writing the target: while the fan is
        // still in auto mode the SMC keeps rewriting F{i}Tg, so a target written
        // first gets stomped in the gap between the two writes (observed on
        // MacBookPro18,2: target reverted 3000 -> 1522 before mode flip landed).
        self.write_fan_mode(index, true)?;
        let applied_rpm = self.write_fan_target_clamped(index, requested_rpm, min_rpm, max_rpm)?;

        Ok(SetOutcome {
            requested_rpm,
            applied_rpm,
            min_rpm,
            max_rpm,
        })
    }

    pub fn restore_auto_all(&self) -> Result<Vec<(usize, SmcError)>, SmcError> {
        let fan_count = self.fan_count()?;
        let mut failures = Vec::new();

        for index in 0..fan_count {
            if let Err(error) = self.write_fan_mode(index, false) {
                failures.push((index, error));
            }
        }

        Ok(failures)
    }

    fn validate_fan_index(&self, index: usize) -> Result<(), SmcError> {
        let fan_count = self.fan_count()?;
        if index >= fan_count {
            return Err(SmcError::new(format!(
                "fan index {index} is out of range; this Mac reports {fan_count} fan(s)"
            )));
        }
        if index > 9 {
            return Err(SmcError::new(format!(
                "fan index {index} cannot be represented by a four-character SMC key"
            )));
        }
        Ok(())
    }

    fn read_fan_numeric(&self, index: usize, suffix: [u8; 2]) -> Result<f64, SmcError> {
        let key = fan_key(index, suffix)?;
        self.read_numeric(key)
            .map_err(|error| error.context(format!("failed to read {}", key_name(key))))
    }

    fn read_fan_mode(&self, index: usize) -> Result<FanMode, SmcError> {
        let (key, value) = read_fan_mode_control(index, |key| self.read_integer(key))?;
        let value = if key == key_from_bytes(*b"FS! ") {
            u64::from(value & (1_u64 << index) != 0)
        } else {
            value
        };
        Ok(match value {
            0 => FanMode::Auto,
            1 => FanMode::Forced,
            value => FanMode::Unknown(value),
        })
    }

    fn write_fan_target_clamped(
        &self,
        index: usize,
        requested_rpm: f64,
        min_rpm: f64,
        max_rpm: f64,
    ) -> Result<f64, SmcError> {
        // Keep clamping adjacent to the only target-key write so future callers cannot bypass it.
        let applied_rpm = requested_rpm.clamp(min_rpm, max_rpm);
        if applied_rpm != requested_rpm {
            eprintln!(
                "warning: requested fan {index} RPM {requested_rpm:.2} is outside \
                 [{min_rpm:.2}, {max_rpm:.2}]; clamped to {applied_rpm:.2}"
            );
        }

        let key = fan_key(index, *b"Tg")?;
        self.write_numeric(
            key,
            applied_rpm,
            format!("set fan {index} target RPM after clamping to [{min_rpm:.2}, {max_rpm:.2}]"),
        )?;
        Ok(applied_rpm)
    }

    fn write_fan_mode(&self, index: usize, forced: bool) -> Result<(), SmcError> {
        let (key, old_value) = read_fan_mode_control(index, |key| self.read_integer(key))?;
        let value = if key == key_from_bytes(*b"FS! ") {
            let fan_bit = 1_u64 << index;
            if forced { old_value | fan_bit } else { old_value & !fan_bit }
        } else {
            u64::from(forced)
        };
        let reason = if forced {
            format!("enable forced mode for fan {index}")
        } else {
            format!("restore automatic mode for fan {index}")
        };
        self.write_integer(key, value, reason)
    }

    fn read_integer(&self, key: u32) -> Result<u64, SmcError> {
        let value = self.read_numeric(key)?;
        if !value.is_finite() || value < 0.0 || value > u64::MAX as f64 {
            return Err(SmcError::new(format!(
                "{} value {value} cannot be represented as an unsigned integer",
                key_name(key)
            )));
        }
        Ok(value.round() as u64)
    }

    fn read_numeric(&self, key: u32) -> Result<f64, SmcError> {
        let info = self.key_info(key)?;
        self.read_numeric_with_info(key, info)
    }

    fn read_numeric_with_info(&self, key: u32, info: KeyInfo) -> Result<f64, SmcError> {
        let data = self.read_raw_with_info(key, info)?;
        decode_numeric(key, info, &data)
    }

    fn key_info(&self, key: u32) -> Result<KeyInfo, SmcError> {
        let input = SmcKeyData {
            key,
            data8: SMC_GET_KEY_INFO,
            ..SmcKeyData::default()
        };
        let output = self.call(&input, "kSMCGetKeyInfo")?;
        if output.key_info.data_size as usize > output.bytes.len() {
            return Err(SmcError::new(format!(
                "{} reports unsupported data size {}",
                key_name(key),
                output.key_info.data_size
            )));
        }
        Ok(KeyInfo {
            data_size: output.key_info.data_size,
            data_type: output.key_info.data_type,
        })
    }

    fn key_at_index(&self, index: u32) -> Result<u32, SmcError> {
        let input = SmcKeyData {
            data8: SMC_GET_KEY_FROM_INDEX,
            data32: index,
            ..SmcKeyData::default()
        };
        let output = self.call(&input, "kSMCGetKeyFromIndex")?;
        Ok(output.key)
    }

    fn read_raw_with_info(&self, key: u32, info: KeyInfo) -> Result<Vec<u8>, SmcError> {
        let input = SmcKeyData {
            key,
            key_info: SmcKeyDataKeyInfo {
                data_size: info.data_size,
                ..SmcKeyDataKeyInfo::default()
            },
            data8: SMC_READ_KEY,
            ..SmcKeyData::default()
        };
        let output = self.call(&input, "kSMCReadKey")?;
        Ok(output.bytes[..info.data_size as usize].to_vec())
    }

    fn write_integer(&self, key: u32, value: u64, reason: String) -> Result<(), SmcError> {
        let info = self.key_info(key)?;
        let bytes = encode_integer(key, info, value)?;
        self.write_raw(key, info, &bytes, value.to_string(), &reason)
    }

    fn write_numeric(&self, key: u32, value: f64, reason: String) -> Result<(), SmcError> {
        let info = self.key_info(key)?;
        let bytes = encode_numeric(key, info, value)?;
        self.write_raw(key, info, &bytes, format!("{value:.2}"), &reason)
    }

    fn write_raw(
        &self,
        key: u32,
        info: KeyInfo,
        bytes: &[u8],
        display_value: String,
        reason: &str,
    ) -> Result<(), SmcError> {
        ensure_write_key_allowed(key)?;
        if bytes.len() != info.data_size as usize {
            return Err(SmcError::new(format!(
                "{} write has {} bytes but key expects {}",
                key_name(key),
                bytes.len(),
                info.data_size
            )));
        }

        let mut input = SmcKeyData {
            key,
            key_info: SmcKeyDataKeyInfo {
                data_size: info.data_size,
                ..SmcKeyDataKeyInfo::default()
            },
            data8: SMC_WRITE_KEY,
            ..SmcKeyData::default()
        };
        input.bytes[..bytes.len()].copy_from_slice(bytes);

        println!(
            "SMC write: key={} value={} reason={reason}",
            key_name(key),
            display_value
        );
        self.call(&input, "kSMCWriteKey")?;
        Ok(())
    }

    fn call(&self, input: &SmcKeyData, operation: &str) -> Result<SmcKeyData, SmcError> {
        let mut output = SmcKeyData::default();
        let mut output_size = size_of::<SmcKeyData>();
        let result = unsafe {
            IOConnectCallStructMethod(
                self.connection,
                SMC_SELECTOR,
                std::ptr::from_ref(input).cast(),
                size_of::<SmcKeyData>(),
                std::ptr::from_mut(&mut output).cast(),
                &mut output_size,
            )
        };
        if result != KERN_SUCCESS {
            return Err(SmcError::new(format!(
                "{operation} for {} failed with IOKit code {result:#x}",
                key_name(input.key)
            )));
        }
        if output_size != size_of::<SmcKeyData>() {
            return Err(SmcError::new(format!(
                "{operation} for {} returned {output_size} bytes; expected {}",
                key_name(input.key),
                size_of::<SmcKeyData>()
            )));
        }
        if output.result != 0 {
            return Err(SmcError::new(format!(
                "{operation} for {} failed with SMC result {:#x}, status {:#x}",
                key_name(input.key),
                output.result,
                output.status
            )));
        }
        Ok(output)
    }
}

impl Drop for SmcClient {
    fn drop(&mut self) {
        unsafe {
            IOServiceClose(self.connection);
        }
    }
}

fn key_from_bytes(bytes: [u8; 4]) -> u32 {
    u32::from_be_bytes(bytes)
}

fn key_name(key: u32) -> String {
    key.to_be_bytes()
        .into_iter()
        .map(|byte| {
            if byte.is_ascii_graphic() || byte == b' ' {
                char::from(byte)
            } else {
                '?'
            }
        })
        .collect()
}

fn type_name(data_type: u32) -> String {
    key_name(data_type)
}

fn fan_key(index: usize, suffix: [u8; 2]) -> Result<u32, SmcError> {
    let digit = u8::try_from(index)
        .ok()
        .and_then(|value| value.checked_add(b'0'))
        .filter(u8::is_ascii_digit)
        .ok_or_else(|| {
            SmcError::new(format!(
                "fan index {index} cannot be represented by a four-character SMC key"
            ))
        })?;
    Ok(key_from_bytes([b'F', digit, suffix[0], suffix[1]]))
}

// The current machine exposes F0md/F1md; older AppleSMC versions use
// F0Md/F1Md or the shared FS! bitmask. Reads and writes must choose the
// same supported control, while preserving other fans' shared mask bits.
fn read_fan_mode_control(
    index: usize,
    mut read: impl FnMut(u32) -> Result<u64, SmcError>,
) -> Result<(u32, u64), SmcError> {
    let candidates = [fan_key(index, *b"Md")?, fan_key(index, *b"md")?, key_from_bytes(*b"FS! ")];
    let mut errors = Vec::new();
    for key in candidates {
        match read(key) {
            Ok(value) => return Ok((key, value)),
            Err(error) => errors.push(format!("{}: {error}", key_name(key))),
        }
    }
    Err(SmcError::new(format!("no readable mode control for fan {index}; {}", errors.join("; "))))
}

fn ensure_write_key_allowed(key: u32) -> Result<(), SmcError> {
    let bytes = key.to_be_bytes();
    let is_shared_mode = bytes == *b"FS! ";
    let is_fan_key = bytes[0] == b'F'
        && bytes[1].is_ascii_digit()
        && (bytes[2..] == *b"Tg" || bytes[2..] == *b"Md" || bytes[2..] == *b"md");
    if is_shared_mode || is_fan_key {
        Ok(())
    } else {
        Err(SmcError::new(format!(
            "refusing write to non-whitelisted SMC key {}",
            key_name(key)
        )))
    }
}

fn require_size(key: u32, info: KeyInfo, expected: usize) -> Result<(), SmcError> {
    if info.data_size as usize == expected {
        Ok(())
    } else {
        Err(SmcError::new(format!(
            "{} type {} has size {}, expected {expected}",
            key_name(key),
            type_name(info.data_type),
            info.data_size
        )))
    }
}

fn decode_numeric(key: u32, info: KeyInfo, bytes: &[u8]) -> Result<f64, SmcError> {
    match info.data_type {
        TYPE_FLT => {
            require_size(key, info, 4)?;
            Ok(f32::from_le_bytes(bytes[..4].try_into().unwrap()).into())
        }
        TYPE_UI8 => {
            require_size(key, info, 1)?;
            Ok(f64::from(bytes[0]))
        }
        TYPE_UI16 => {
            require_size(key, info, 2)?;
            Ok(f64::from(u16::from_be_bytes(
                bytes[..2].try_into().unwrap(),
            )))
        }
        TYPE_UI32 => {
            require_size(key, info, 4)?;
            Ok(f64::from(u32::from_be_bytes(
                bytes[..4].try_into().unwrap(),
            )))
        }
        TYPE_FPE2 => {
            require_size(key, info, 2)?;
            let raw = u16::from_be_bytes(bytes[..2].try_into().unwrap());
            Ok(f64::from(raw) / 4.0)
        }
        TYPE_SP78 => {
            require_size(key, info, 2)?;
            let raw = i16::from_be_bytes(bytes[..2].try_into().unwrap());
            Ok(f64::from(raw) / 256.0)
        }
        data_type => Err(SmcError::new(format!(
            "{} has unsupported data type {}",
            key_name(key),
            type_name(data_type)
        ))),
    }
}

fn encode_numeric(key: u32, info: KeyInfo, value: f64) -> Result<Vec<u8>, SmcError> {
    if !value.is_finite() {
        return Err(SmcError::new(format!(
            "cannot encode non-finite value {value} for {}",
            key_name(key)
        )));
    }
    match info.data_type {
        TYPE_FLT => {
            require_size(key, info, 4)?;
            if value < f32::MIN as f64 || value > f32::MAX as f64 {
                return Err(SmcError::new(format!(
                    "value {value} is outside flt range for {}",
                    key_name(key)
                )));
            }
            Ok((value as f32).to_le_bytes().to_vec())
        }
        TYPE_UI8 | TYPE_UI16 | TYPE_UI32 | TYPE_FPE2 | TYPE_SP78 => {
            encode_compatible_number(key, info, value)
        }
        data_type => Err(SmcError::new(format!(
            "{} has unsupported data type {}",
            key_name(key),
            type_name(data_type)
        ))),
    }
}

fn encode_integer(key: u32, info: KeyInfo, value: u64) -> Result<Vec<u8>, SmcError> {
    match info.data_type {
        TYPE_UI8 => {
            require_size(key, info, 1)?;
            Ok(vec![u8::try_from(value).map_err(|_| {
                SmcError::new(format!(
                    "value {value} is outside ui8 range for {}",
                    key_name(key)
                ))
            })?])
        }
        TYPE_UI16 => {
            require_size(key, info, 2)?;
            Ok(u16::try_from(value)
                .map_err(|_| {
                    SmcError::new(format!(
                        "value {value} is outside ui16 range for {}",
                        key_name(key)
                    ))
                })?
                .to_be_bytes()
                .to_vec())
        }
        TYPE_UI32 => {
            require_size(key, info, 4)?;
            Ok(u32::try_from(value)
                .map_err(|_| {
                    SmcError::new(format!(
                        "value {value} is outside ui32 range for {}",
                        key_name(key)
                    ))
                })?
                .to_be_bytes()
                .to_vec())
        }
        TYPE_FLT | TYPE_FPE2 | TYPE_SP78 => encode_numeric(key, info, value as f64),
        data_type => Err(SmcError::new(format!(
            "{} has unsupported data type {}",
            key_name(key),
            type_name(data_type)
        ))),
    }
}

fn encode_compatible_number(key: u32, info: KeyInfo, value: f64) -> Result<Vec<u8>, SmcError> {
    match info.data_type {
        TYPE_UI8 => {
            require_size(key, info, 1)?;
            let rounded = value.round();
            if !(0.0..=u8::MAX as f64).contains(&rounded) {
                return Err(SmcError::new(format!(
                    "value {value} is outside ui8 range for {}",
                    key_name(key)
                )));
            }
            Ok(vec![rounded as u8])
        }
        TYPE_UI16 => {
            require_size(key, info, 2)?;
            let rounded = value.round();
            if !(0.0..=u16::MAX as f64).contains(&rounded) {
                return Err(SmcError::new(format!(
                    "value {value} is outside ui16 range for {}",
                    key_name(key)
                )));
            }
            Ok((rounded as u16).to_be_bytes().to_vec())
        }
        TYPE_UI32 => {
            require_size(key, info, 4)?;
            let rounded = value.round();
            if !(0.0..=u32::MAX as f64).contains(&rounded) {
                return Err(SmcError::new(format!(
                    "value {value} is outside ui32 range for {}",
                    key_name(key)
                )));
            }
            Ok((rounded as u32).to_be_bytes().to_vec())
        }
        TYPE_FPE2 => {
            require_size(key, info, 2)?;
            let raw = (value * 4.0).round();
            if !(0.0..=u16::MAX as f64).contains(&raw) {
                return Err(SmcError::new(format!(
                    "value {value} is outside fpe2 range for {}",
                    key_name(key)
                )));
            }
            Ok((raw as u16).to_be_bytes().to_vec())
        }
        TYPE_SP78 => {
            require_size(key, info, 2)?;
            let raw = (value * 256.0).round();
            if !(i16::MIN as f64..=i16::MAX as f64).contains(&raw) {
                return Err(SmcError::new(format!(
                    "value {value} is outside sp78 range for {}",
                    key_name(key)
                )));
            }
            Ok((raw as i16).to_be_bytes().to_vec())
        }
        _ => unreachable!(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn protocol_layout_is_apple_silicon_layout() {
        assert_eq!(size_of::<SmcKeyDataVers>(), 6);
        assert_eq!(size_of::<SmcKeyDataPLimitData>(), 16);
        assert_eq!(size_of::<SmcKeyDataKeyInfo>(), 12);
        assert_eq!(size_of::<SmcKeyData>(), 80);
    }

    #[test]
    fn write_whitelist_rejects_every_other_key_shape() {
        assert!(ensure_write_key_allowed(key_from_bytes(*b"F0Tg")).is_ok());
        assert!(ensure_write_key_allowed(key_from_bytes(*b"F1Md")).is_ok());
        assert!(ensure_write_key_allowed(key_from_bytes(*b"FS! ")).is_ok());
        assert!(ensure_write_key_allowed(key_from_bytes(*b"F0Mn")).is_err());
        assert!(ensure_write_key_allowed(key_from_bytes(*b"TC0D")).is_err());
    }

    #[test]
    fn float_values_use_little_endian_bytes() {
        let info = KeyInfo {
            data_size: 4,
            data_type: TYPE_FLT,
        };
        let encoded = encode_numeric(key_from_bytes(*b"F0Tg"), info, 2048.5).unwrap();
        assert_eq!(encoded, 2048.5_f32.to_le_bytes());
        assert_eq!(
            decode_numeric(key_from_bytes(*b"F0Tg"), info, &encoded).unwrap(),
            2048.5
        );
    }
}

#[cfg(test)]
mod mode_compatibility_tests {
    use super::*;

    #[test]
    fn mode_control_supports_legacy_modern_and_shared_keys() {
        for (supported, value) in [("F1Md", 1), ("F1md", 0), ("FS! ", 5)] {
            let supported = key_from_bytes(supported.as_bytes().try_into().unwrap());
            let (selected, observed) = read_fan_mode_control(1, |key| {
                if key == supported { Ok(value) } else { Err(SmcError::new("key unavailable")) }
            }).unwrap();
            assert_eq!(selected, supported);
            assert_eq!(observed, value);
            assert!(ensure_write_key_allowed(selected).is_ok());
        }
    }

    #[test]
    fn mode_control_prefers_the_legacy_direct_key_when_supported() {
        let mut attempts = Vec::new();
        let (selected, _) = read_fan_mode_control(0, |key| { attempts.push(key); Ok(0) }).unwrap();
        assert_eq!(key_name(selected), "F0Md");
        assert_eq!(attempts.len(), 1);
    }

    #[test]
    fn missing_mode_controls_report_each_original_error() {
        let error = read_fan_mode_control(0, |key| Err(SmcError::new(format!("read denied {}", key_name(key))))).unwrap_err().to_string();
        for name in ["F0Md", "F0md", "FS! "] { assert!(error.contains(&format!("read denied {name}"))); }
    }
}
