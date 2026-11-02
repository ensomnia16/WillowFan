use std::time::Duration;

pub const WAKE_GAP: Duration = Duration::from_secs(10);

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum FanCurve {
    Quiet,
    Balanced,
    Active,
}

impl FanCurve {
    pub fn from_name(value: &str) -> Option<Self> {
        match value {
            "quiet" => Some(Self::Quiet),
            "balanced" => Some(Self::Balanced),
            "active" => Some(Self::Active),
            _ => None,
        }
    }

    pub fn name(self) -> &'static str {
        match self {
            Self::Quiet => "quiet",
            Self::Balanced => "balanced",
            Self::Active => "active",
        }
    }

    fn points(self) -> &'static [(f64, f64)] {
        match self {
            Self::Quiet => &[(40.0, 0.0), (55.0, 0.0), (65.0, 0.10), (75.0, 0.30), (85.0, 0.55), (95.0, 0.82), (100.0, 1.0)],
            Self::Balanced => &[(40.0, 0.0), (50.0, 0.10), (60.0, 0.22), (70.0, 0.42), (80.0, 0.65), (90.0, 0.85), (100.0, 1.0)],
            Self::Active => &[(40.0, 0.10), (50.0, 0.24), (60.0, 0.40), (70.0, 0.58), (80.0, 0.75), (90.0, 0.90), (100.0, 1.0)],
        }
    }
}

/// Returns a fraction of the hardware [minimum, maximum] RPM range.
/// `base` shifts curve temperatures relative to 60 °C. A measured 100 °C
/// always requests full speed regardless of the selected curve or base.
pub fn curve_fraction(curve: FanCurve, temperature: f64, base: f64) -> f64 {
    if !temperature.is_finite() || !base.is_finite() || temperature >= 100.0 {
        return 1.0;
    }
    let adjusted = temperature - (base - 60.0);
    let points = curve.points();
    if adjusted <= points[0].0 {
        return points[0].1;
    }
    for pair in points.windows(2) {
        let (low_t, low_speed) = pair[0];
        let (high_t, high_speed) = pair[1];
        if adjusted <= high_t {
            let position = (adjusted - low_t) / (high_t - low_t);
            return (low_speed + position * (high_speed - low_speed)).clamp(0.0, 1.0);
        }
    }
    1.0
}

pub fn slew_limited(previous: f64, desired: f64) -> f64 {
    desired.clamp(previous - 125.0, previous + 250.0)
}

pub fn outside_deadband(previous: f64, desired: f64) -> bool {
    (desired - previous).abs() >= 50.0
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn curves_are_ordered_and_do_not_max_out_at_ordinary_hotspots() {
        for temperature in [50.0, 60.0, 70.0, 80.0, 90.0] {
            let quiet = curve_fraction(FanCurve::Quiet, temperature, 60.0);
            let balanced = curve_fraction(FanCurve::Balanced, temperature, 60.0);
            let active = curve_fraction(FanCurve::Active, temperature, 60.0);
            assert!(quiet <= balanced && balanced <= active);
            assert!(active < 1.0);
        }
        assert_eq!(curve_fraction(FanCurve::Active, 100.0, 70.0), 1.0);
    }

    #[test]
    fn every_curve_rises_with_temperature() {
        for curve in [FanCurve::Quiet, FanCurve::Balanced, FanCurve::Active] {
            let values: Vec<_> = (40..=100).map(|t| curve_fraction(curve, t as f64, 60.0)).collect();
            assert!(values.windows(2).all(|pair| pair[0] <= pair[1]));
        }
    }

    #[test]
    fn warmer_base_delays_ramp_but_not_emergency_full_speed() {
        assert!(curve_fraction(FanCurve::Balanced, 70.0, 55.0)
            > curve_fraction(FanCurve::Balanced, 70.0, 65.0));
        assert_eq!(curve_fraction(FanCurve::Quiet, 100.0, 80.0), 1.0);
    }

    #[test]
    fn slew_limiter_is_asymmetric_and_deadband_avoids_churn() {
        assert_eq!(slew_limited(2_000.0, 3_000.0), 2_250.0);
        assert_eq!(slew_limited(2_000.0, 1_000.0), 1_875.0);
        assert!(!outside_deadband(2_000.0, 2_049.0));
        assert!(outside_deadband(2_000.0, 2_050.0));
    }
}
