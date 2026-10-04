//! Réglages issus des specs `docs/specs/camera.md` et `docs/specs/surface-movement.md`.
//!
//! Les valeurs de référence sont celles mesurées sur *Les Fourmis* (1 u = 1 cm moteur, corps de rayon 14 u).
//! [`Tuning::scaled`] les transpose à un corps de rayon quelconque (spec §8 / §7) : longueurs, vitesses et
//! accélérations × s, angles et vitesses angulaires inchangés, avec s = rayon / 14.

use std::f32::consts::PI;

#[derive(Clone, Debug)]
pub struct Tuning {
    // --- corps & sondes de surface
    pub body_radius: f32,
    /// Nombre de rayons de sonde (CastSamples).
    pub probe_samples: usize,
    /// Portée des sondes, en multiples du rayon.
    pub probe_range: f32,
    /// Marge de contact pour être « posé ».
    pub ground_skin: f32,
    // --- vitesses au sol
    pub walk_speed: f32,
    pub run_speed: f32,
    pub run_accel: f32,
    pub stamina_use_per_s: f32,
    pub stamina_recharge_per_s: f32,
    pub stamina_rested: f32,
    // --- orientation du corps (rad/s, interpolation exponentielle)
    pub up_interp_idle: f32,
    pub up_interp_walk: f32,
    pub forward_interp: f32,
    // --- air
    pub gravity: f32,
    pub max_fall_speed: f32,
    pub max_air_h_speed: f32,
    pub air_control_accel: f32,
    pub air_h_damping: f32,
    pub max_air_control_angle: f32,
    pub air_up_interp: f32,
    // --- saut / décrochage
    pub jump_strength: f32,
    pub jump_charge_duration: f32,
    pub jump_elevation: f32,
    pub jump_clamp_from_world_up: f32,
    pub jump_exit_duration: f32,
    pub jump_stamina_cost: f32,
    pub drop_charge_duration: f32,
    pub drop_cos_threshold: f32,
    // --- caméra
    pub cam_rotation_speed: f32,
    pub cam_pitch_limit: f32,
    pub cam_pivot_offset: f32,
    pub leash_gain: f32,
    pub leash_exponent: f32,
    pub leash_walk: f32,
    pub leash_run: f32,
    pub leash_transition_speed: f32,
    pub arm_lengths: [f32; 3],
    pub cam_sphere_radius: f32,
    pub cam_zoom_out_speed: f32,
    pub cam_near: f32,
    pub cam_fov_horizontal: f32,
    pub pawn_hide_distance: f32,
}

impl Tuning {
    /// Valeurs mesurées sur Les Fourmis (unités du jeu, corps R = 14 u).
    pub fn ant() -> Self {
        Self {
            body_radius: 14.0,
            probe_samples: 32,
            probe_range: 2.2,
            ground_skin: 1.4, // 0,1 R : plus robuste que les 0,02 u du jeu avec des rayons discrets
            walk_speed: 180.0,
            run_speed: 700.0,
            run_accel: 1000.0,
            stamina_use_per_s: 0.05,
            stamina_recharge_per_s: 0.025,
            stamina_rested: 0.25,
            up_interp_idle: 2.0 * PI,
            // WalkUpInterpSpeed (1,5π) × MaxWalkRotationSpeedBoost (2,5) ≈ 11,8 rad/s : reproduit le passage
            // sol → mur mesuré (~0,2 s), voir tests.
            up_interp_walk: 1.5 * PI * 2.5,
            forward_interp: 4.5 * PI,
            gravity: 980.0,
            max_fall_speed: 2000.0,
            max_air_h_speed: 900.0,
            air_control_accel: 400.0,
            air_h_damping: 400.0,
            max_air_control_angle: PI / 6.0,
            air_up_interp: PI,
            jump_strength: 700.0,
            jump_charge_duration: 0.5,
            jump_elevation: 34f32.to_radians(),
            jump_clamp_from_world_up: 2.2,
            jump_exit_duration: 0.1,
            jump_stamina_cost: 0.1,
            drop_charge_duration: 0.15,
            drop_cos_threshold: 0.1,
            cam_rotation_speed: 180f32.to_radians(),
            cam_pitch_limit: 86f32.to_radians(),
            cam_pivot_offset: 20.0,
            leash_gain: 2.6,
            leash_exponent: 1.2,
            leash_walk: 27.0,
            leash_run: 75.0, // jeu : 100 ; 75 reproduit l'excès max mesuré (65-73)
            leash_transition_speed: 600.0,
            arm_lengths: [150.0, 300.0, 500.0],
            cam_sphere_radius: 8.0,
            cam_zoom_out_speed: 200.0,
            cam_near: 5.0,
            cam_fov_horizontal: 90f32.to_radians(),
            pawn_hide_distance: 50.0,
        }
    }

    /// Transpose à un corps de rayon `radius` (même unité que le reste du monde).
    pub fn scaled(radius: f32) -> Self {
        let a = Self::ant();
        let s = radius / a.body_radius;
        Self {
            body_radius: radius,
            ground_skin: a.ground_skin * s,
            walk_speed: a.walk_speed * s,
            run_speed: a.run_speed * s,
            run_accel: a.run_accel * s,
            gravity: a.gravity * s,
            max_fall_speed: a.max_fall_speed * s,
            max_air_h_speed: a.max_air_h_speed * s,
            air_control_accel: a.air_control_accel * s,
            air_h_damping: a.air_h_damping * s,
            jump_strength: a.jump_strength * s,
            cam_pivot_offset: a.cam_pivot_offset * s,
            // v = A·d^P n'est pas linéaire : A' = A · s^(1-P) (camera.md §8)
            leash_gain: a.leash_gain * s.powf(1.0 - a.leash_exponent),
            leash_walk: a.leash_walk * s,
            leash_run: a.leash_run * s,
            leash_transition_speed: a.leash_transition_speed * s,
            arm_lengths: a.arm_lengths.map(|l| l * s),
            cam_sphere_radius: a.cam_sphere_radius * s,
            cam_zoom_out_speed: a.cam_zoom_out_speed * s,
            cam_near: a.cam_near * s,
            pawn_hide_distance: a.pawn_hide_distance * s,
            ..a
        }
    }
}
