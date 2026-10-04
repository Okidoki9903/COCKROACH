//! Caméra 3e personne à hauteur d'insecte — implémentation de `docs/specs/camera.md`.
//!
//! Orbite libre en repère monde (yaw/pitch, roll = 0, jamais recentrée), pivot = corps + offset le long de
//! l'up du corps, point de suivi retardé par une laisse (v = A·d^P, borné par L), bras fixe, collision
//! sphérique : rentrée instantanée, ressortie à vitesse constante.

use bevy::math::{EulerRot, Quat, Vec2, Vec3};

use crate::query::SurfaceQuery;
use crate::tuning::Tuning;

#[derive(Clone, Copy, Debug)]
pub struct CameraOutput {
    pub position: Vec3,
    pub rotation: Quat,
    pub pivot: Vec3,
    /// Distance caméra ↔ pivot.
    pub distance: f32,
    /// Le corps doit être masqué (caméra trop proche).
    pub hide_pawn: bool,
}

#[derive(Clone, Debug)]
pub struct CameraRig {
    pub yaw: f32,
    pub pitch: f32,
    /// Indice dans `Tuning::arm_lengths` (0 = proche, 1 = moyen, 2 = loin).
    pub arm_index: usize,
    follow: Option<Vec3>,
    leash: f32,
    /// Limite de collision du bras (∞ = libre).
    limit: f32,
}

impl CameraRig {
    pub fn new(yaw: f32, pitch: f32) -> Self {
        Self { yaw, pitch, arm_index: 1, follow: None, leash: f32::NAN, limit: f32::INFINITY }
    }

    pub fn rotation(&self) -> Quat {
        Quat::from_euler(EulerRot::YXZ, self.yaw, self.pitch, 0.0)
    }

    pub fn forward(&self) -> Vec3 {
        self.rotation() * Vec3::NEG_Z
    }

    pub fn up(&self) -> Vec3 {
        self.rotation() * Vec3::Y
    }

    pub fn cycle_arm(&mut self) {
        self.arm_index = (self.arm_index + 1) % 3;
    }

    /// Rotation : `stick` en [-1, 1] (vitesse = RotationSpeed × stick, sans lissage) et `mouse` en radians.
    /// Stick à droite = tourner à droite ; stick en haut = regarder en haut.
    pub fn rotate(&mut self, stick: Vec2, mouse: Vec2, t: &Tuning, dt: f32) {
        let s = stick.clamp_length_max(1.0) * t.cam_rotation_speed * dt;
        self.yaw -= s.x + mouse.x;
        self.pitch = (self.pitch + s.y + mouse.y).clamp(-t.cam_pitch_limit, t.cam_pitch_limit);
    }

    pub fn update(
        &mut self,
        body_position: Vec3,
        body_up: Vec3,
        running: bool,
        q: &impl SurfaceQuery,
        t: &Tuning,
        dt: f32,
    ) -> CameraOutput {
        let pivot = body_position + body_up * t.cam_pivot_offset;

        // Laisse : longueur qui transite entre marche et course.
        let leash_target = if running { t.leash_run } else { t.leash_walk };
        if self.leash.is_nan() {
            self.leash = leash_target;
        }
        self.leash = move_towards(self.leash, leash_target, t.leash_transition_speed * dt);

        // Point de suivi rappelé à v = A·d^P, puis borné par la laisse.
        let f = self.follow.get_or_insert(pivot);
        let e = pivot - *f;
        let d = e.length();
        if d > 1e-6 {
            let step = (t.leash_gain * d.powf(t.leash_exponent) * dt).min(d);
            *f += e / d * step;
        }
        let e = pivot - *f;
        let d = e.length();
        if d > self.leash {
            *f = pivot - e / d * self.leash;
        }

        // Bras + collision (depuis le pivot pour ne jamais passer derrière un mur à cause du retard).
        let desired = *f - self.forward() * t.arm_lengths[self.arm_index];
        let to = desired - pivot;
        let dist = to.length().max(1e-4);
        let dir = to / dist;
        let hit = q.sphere(pivot, dir, t.cam_sphere_radius, dist);
        let allowed = hit.map_or(dist, |h| h.distance);
        if allowed < self.limit {
            self.limit = allowed; // rentrée instantanée
        } else {
            self.limit += t.cam_zoom_out_speed * dt; // ressortie à vitesse constante
            if hit.is_none() && self.limit >= dist {
                self.limit = f32::INFINITY;
            }
        }
        let cam_dist = dist.min(self.limit);
        let position = pivot + dir * cam_dist;

        CameraOutput {
            position,
            rotation: self.rotation(),
            pivot,
            distance: cam_dist,
            hide_pawn: position.distance(body_position) < t.pawn_hide_distance,
        }
    }
}

fn move_towards(current: f32, target: f32, max_delta: f32) -> f32 {
    if (target - current).abs() <= max_delta {
        target
    } else {
        current + (target - current).signum() * max_delta
    }
}
