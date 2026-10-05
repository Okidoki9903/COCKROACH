//! Perception humaine et suspicion 0-100 — implémentation de `docs/specs/perception.md` partie B.
//!
//! Portée et bandes reprises de Les Fourmis (1500 u = 107 R ; bande brûlante 250 u = 18 R) ; regard, ligne de
//! vue, mouvement, lumière et type de surface ajoutés pour des humains (décisions de design, spec §B).

use bevy::math::Vec3;

use crate::query::SurfaceQuery;

#[derive(Clone, Debug)]
pub struct PerceptionTuning {
    pub range_max: f32,
    pub range_near: f32,
    /// Angle total du cône central (rad).
    pub cone_focus: f32,
    /// Angle total du cône périphérique (rad).
    pub cone_peripheral: f32,
    pub peripheral_gain: f32,
    pub speed_ref: f32,
    pub idle_floor: f32,
    /// Suspicion gagnée par seconde à visibilité 1.
    pub gain: f32,
    pub decay: f32,
    /// Délai avant que la suspicion ne retombe (s).
    pub grace: f32,
    pub wall_gain: f32,
    pub ceiling_gain: f32,
    /// Facteur de lumière dans l'ombre.
    pub shadow_light: f32,
    pub notice: f32,
    pub search: f32,
    pub detect: f32,
    /// Zone rouge autour du pied (écrasement possible si suspicion ≥ search).
    pub red_zone: f32,
    pub yellow_ratio: f32,
}

impl PerceptionTuning {
    /// Réglages de départ de la spec pour un humain dont les yeux sont à `eye_height`, observant un cafard
    /// de rayon `r`. Les portées sont relatives à l'observateur (spec §B.2).
    pub fn human(eye_height: f32, r: f32) -> Self {
        Self {
            range_max: 2.8 * eye_height,
            range_near: 0.75 * eye_height,
            cone_focus: 30f32.to_radians(),
            cone_peripheral: 120f32.to_radians(),
            peripheral_gain: 0.3,
            speed_ref: 50.0 * r,
            idle_floor: 0.05,
            gain: 100.0 / 1.5,
            decay: 8.0,
            grace: 3.0,
            wall_gain: 0.8,
            ceiling_gain: 1.2,
            shadow_light: 0.3,
            notice: 30.0,
            search: 60.0,
            detect: 100.0,
            red_zone: 3.0 * r,
            yellow_ratio: 2.5,
        }
    }
}

/// Un observateur : position des yeux et direction du regard (unitaire).
#[derive(Clone, Copy, Debug)]
pub struct Observer {
    pub eye: Vec3,
    pub gaze: Vec3,
}

/// Ce que l'observateur peut voir du cafard.
#[derive(Clone, Copy, Debug)]
pub struct Target {
    pub position: Vec3,
    /// Normale de la surface sur laquelle il se trouve.
    pub up: Vec3,
    pub speed: f32,
    /// 1 = plein jour, `shadow_light` à l'ombre.
    pub light: f32,
    pub body_radius: f32,
}

/// Détail du calcul (pour le HUD et le debug).
#[derive(Clone, Copy, Debug, Default)]
pub struct Visibility {
    pub value: f32,
    pub distance: f32,
    pub line_of_sight: bool,
    pub f_dist: f32,
    pub f_cone: f32,
    pub f_move: f32,
}

fn smoothstep(edge0: f32, edge1: f32, x: f32) -> f32 {
    let t = ((x - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
    t * t * (3.0 - 2.0 * t)
}

pub fn visibility(obs: &Observer, target: &Target, t: &PerceptionTuning, q: &impl SurfaceQuery) -> Visibility {
    // On vise un point légèrement décollé de la surface, pour ne pas toucher le support du cafard.
    let aim = target.position + target.up * target.body_radius * 0.5;
    let to = aim - obs.eye;
    let d = to.length();
    let mut v = Visibility { distance: d, ..Default::default() };
    if d > t.range_max || d < 1e-4 {
        return v;
    }
    let dir = to / d;
    v.line_of_sight = match q.ray(obs.eye, dir, d) {
        Some(h) => h.distance >= d - target.body_radius * 1.5,
        None => true,
    };
    if !v.line_of_sight {
        return v;
    }
    v.f_dist = smoothstep(t.range_max, t.range_near, d);
    let angle = obs.gaze.angle_between(dir);
    v.f_cone = if angle < t.cone_focus * 0.5 {
        1.0
    } else if angle < t.cone_peripheral * 0.5 {
        t.peripheral_gain
    } else {
        0.0
    };
    v.f_move = (target.speed / t.speed_ref).clamp(t.idle_floor, 1.0);
    let up_y = target.up.y;
    let f_surf = if up_y > 0.7 {
        1.0
    } else if up_y < -0.7 {
        t.ceiling_gain
    } else {
        t.wall_gain
    };
    v.value = v.f_dist * v.f_cone * v.f_move * target.light.clamp(0.0, 1.0) * f_surf;
    v
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Awareness {
    Calm,
    Notice,
    Search,
    Detected,
}

#[derive(Clone, Debug, Default)]
pub struct Suspicion {
    pub value: f32,
    pub since_seen: f32,
    pub last_seen: Option<Vec3>,
}

impl Suspicion {
    pub fn update(&mut self, visible: f32, seen_at: Vec3, t: &PerceptionTuning, dt: f32) {
        if visible > 1e-4 {
            self.value = (self.value + visible * t.gain * dt).min(t.detect);
            self.since_seen = 0.0;
            self.last_seen = Some(seen_at);
        } else {
            self.since_seen += dt;
            if self.since_seen > t.grace {
                self.value = (self.value - t.decay * dt).max(0.0);
            }
        }
    }

    pub fn awareness(&self, t: &PerceptionTuning) -> Awareness {
        if self.value >= t.detect {
            Awareness::Detected
        } else if self.value >= t.search {
            Awareness::Search
        } else if self.value >= t.notice {
            Awareness::Notice
        } else {
            Awareness::Calm
        }
    }
}

#[cfg(test)]
mod tests {
    //! Critères d'acceptation de la spec perception §B.4 (cafard R = 1).
    use super::*;
    use crate::query::BoxWorld;

    const R: f32 = 1.0;
    const EYE: f32 = 160.0;
    const DT: f32 = 1.0 / 60.0;

    fn tuning() -> PerceptionTuning {
        PerceptionTuning::human(EYE, R)
    }

    fn roach(at: Vec3, speed: f32, light: f32) -> Target {
        Target { position: at, up: Vec3::Y, speed, light, body_radius: R }
    }

    fn floor() -> BoxWorld {
        BoxWorld::default().with(Vec3::new(0.0, -5.0, 0.0), Vec3::new(2000.0, 10.0, 2000.0))
    }

    /// Humain debout à l'origine (yeux à 160 cm) qui regarde droit vers `at`.
    fn looking_at(at: Vec3) -> Observer {
        let eye = Vec3::new(0.0, EYE, 0.0);
        Observer { eye, gaze: (at - eye).normalize() }
    }

    fn time_to_reach(level: f32, obs: &Observer, target: &Target, q: &BoxWorld, max_s: f32) -> Option<f32> {
        let t = tuning();
        let mut s = Suspicion::default();
        for i in 1..=((max_s / DT) as usize) {
            let v = visibility(obs, target, &t, q);
            s.update(v.value, target.position, &t, DT);
            if s.value >= level {
                return Some(i as f32 * DT);
            }
        }
        None
    }

    #[test]
    fn idle_in_shadow_stays_below_notice() {
        let t = tuning();
        let p = Vec3::new(0.0, R, -150.0); // au sol, à 2,2 m des yeux, en plein centre du regard
        let target = roach(p, 0.0, t.shadow_light);
        assert!(time_to_reach(t.notice, &looking_at(p), &target, &floor(), 10.0).is_none(), "immobile à l'ombre : < 30 en 10 s");
    }

    #[test]
    fn running_in_light_is_detected_fast() {
        let t = tuning();
        let p = Vec3::new(0.0, R, -60.0); // à ses pieds (1,7 m des yeux)
        let target = roach(p, 50.0 * R, 1.0);
        let tt = time_to_reach(t.detect, &looking_at(p), &target, &floor(), 5.0).expect("doit être détecté");
        assert!(tt < 2.0, "détecté en {tt:.2} s (< 2 s attendu)");
    }

    #[test]
    fn far_side_of_the_kitchen_is_noticed_slowly() {
        let t = tuning();
        let p = Vec3::new(0.0, R, -380.0); // ~4,1 m
        let target = roach(p, 50.0 * R, 1.0);
        // près de la portée max : remarqué (tête tournée) mais pas détecté tout de suite
        let notice = time_to_reach(t.notice, &looking_at(p), &target, &floor(), 30.0).expect("remarqué à l'autre bout");
        assert!(notice > 2.0, "plus lent de loin : remarqué en {notice:.2} s");
        assert!(time_to_reach(t.detect, &looking_at(p), &target, &floor(), 5.0).is_none());
    }

    #[test]
    fn hidden_behind_obstacle_is_never_seen() {
        let t = tuning();
        let p = Vec3::new(0.0, R, -60.0);
        let world = floor().with(Vec3::new(0.0, 15.0, -40.0), Vec3::new(40.0, 30.0, 4.0)); // planche entre les deux
        let obs = Observer { eye: Vec3::new(0.0, 20.0, 0.0), gaze: Vec3::NEG_Z };
        let v = visibility(&obs, &roach(p, 50.0, 1.0), &t, &world);
        assert!(!v.line_of_sight && v.value == 0.0);
    }

    #[test]
    fn behind_the_human_is_never_seen() {
        let t = tuning();
        let p = Vec3::new(0.0, R, 40.0);
        let obs = Observer { eye: Vec3::new(0.0, 30.0, 0.0), gaze: Vec3::NEG_Z };
        let v = visibility(&obs, &roach(p, 50.0, 1.0), &t, &floor());
        assert!(v.line_of_sight && v.value == 0.0, "{v:?}");
    }

    #[test]
    fn suspicion_falls_from_60_to_0_within_15_s() {
        let t = tuning();
        let mut s = Suspicion { value: 60.0, ..Default::default() };
        let mut elapsed = 0.0;
        while s.value > 0.0 && elapsed < 30.0 {
            s.update(0.0, Vec3::ZERO, &t, DT);
            elapsed += DT;
        }
        assert!(elapsed < 15.0, "retour à 0 en {elapsed:.1} s");
    }

    #[test]
    fn out_of_range_is_invisible() {
        let t = tuning();
        let p = Vec3::new(0.0, R, -600.0);
        let obs = Observer { eye: Vec3::new(0.0, 30.0, 0.0), gaze: Vec3::NEG_Z };
        assert_eq!(visibility(&obs, &roach(p, 50.0, 1.0), &t, &floor()).value, 0.0);
    }
}
