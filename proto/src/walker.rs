//! Marcheur multi-surfaces — implémentation de `docs/specs/surface-movement.md`.
//!
//! Mouvement cinématique : le corps est une sphère de rayon R qui colle à toute surface. 32 rayons de sonde
//! partent du centre (anneaux autour de -up) ; la normale cible est la moyenne pondérée des normales touchées
//! près du corps, ce qui fait « s'enrouler » le corps autour des arêtes sur un arc de rayon ≈ R (§3.2).
//! Repère monde Bevy : +Y en haut.

use bevy::math::{Quat, Vec2, Vec3};

use crate::query::SurfaceQuery;
use crate::tuning::Tuning;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Mode {
    Idle,
    Walk,
    Run,
    ChargeJump,
    Jump,
    Fall,
}

/// Entrées d'une image. Le stick est interprété dans le repère de la caméra (§4).
#[derive(Clone, Copy, Debug)]
pub struct MoveInput {
    /// x = droite, y = haut ; norme ≤ 1.
    pub stick: Vec2,
    pub run: bool,
    /// Bouton de saut maintenu (saut chargé au relâchement).
    pub jump: bool,
    pub cam_forward: Vec3,
    pub cam_up: Vec3,
}

impl Default for MoveInput {
    fn default() -> Self {
        Self { stick: Vec2::ZERO, run: false, jump: false, cam_forward: Vec3::NEG_Z, cam_up: Vec3::Y }
    }
}

/// Point de surface trouvé par une sonde.
#[derive(Clone, Copy, Debug)]
pub struct Contact {
    pub point: Vec3,
    pub normal: Vec3,
    pub weight: f32,
}

const STICK_DEADZONE: f32 = 0.1;
/// Anneaux de sonde : (angle depuis -up en degrés, nombre de rayons). 1 + 8 + 12 + 11 = 32 (CastSamples).
const PROBE_RINGS: [(f32, usize); 4] = [(0.0, 1), (35.0, 8), (70.0, 12), (100.0, 11)];

#[derive(Clone, Debug)]
pub struct Walker {
    pub position: Vec3,
    pub up: Vec3,
    pub forward: Vec3,
    pub velocity: Vec3,
    pub mode: Mode,
    pub grounded: bool,
    pub stamina: f32,
    run_speed: f32,
    run_locked: bool,
    charge: f32,
    jump_timer: f32,
    /// « Avant écran » de l'image précédente, tant que le stick reste poussé (continuité, §4).
    screen_forward: Option<Vec3>,
    /// Normale cible de la dernière image (debug / HUD).
    pub target_up: Vec3,
    /// Contacts de la dernière image (debug).
    pub contacts: Vec<Contact>,
}

impl Walker {
    pub fn new(position: Vec3, forward: Vec3) -> Self {
        Self {
            position,
            up: Vec3::Y,
            forward: reproject(forward, Vec3::Y, Vec3::NEG_Z),
            velocity: Vec3::ZERO,
            mode: Mode::Idle,
            grounded: true,
            stamina: 1.0,
            run_speed: 0.0,
            run_locked: false,
            charge: 0.0,
            jump_timer: 0.0,
            screen_forward: None,
            target_up: Vec3::Y,
            contacts: Vec::new(),
        }
    }

    pub fn right(&self) -> Vec3 {
        self.forward.cross(self.up).normalize_or_zero()
    }

    /// Lance les 32 sondes autour de -up depuis le centre du corps.
    pub fn probe(&self, q: &impl SurfaceQuery, t: &Tuning) -> Vec<Contact> {
        let r = t.body_radius;
        let range = r * t.probe_range;
        let right = self.right();
        let mut out = Vec::with_capacity(32);
        for (theta_deg, count) in PROBE_RINGS {
            let theta = theta_deg.to_radians();
            for i in 0..count {
                // anneaux décalés d'un demi-pas pour mieux couvrir
                let phi = (i as f32 + 0.5 * (count % 2) as f32) / count as f32 * std::f32::consts::TAU;
                let tangent = self.forward * phi.cos() + right * phi.sin();
                let dir = (-self.up * theta.cos() + tangent * theta.sin()).normalize();
                if let Some(h) = q.ray(self.position, dir, range) {
                    out.push(Contact { point: self.position + dir * h.distance, normal: h.normal, weight: weight(h.distance, r) });
                }
            }
        }
        out
    }

    /// Une image de simulation.
    pub fn step(&mut self, input: &MoveInput, q: &impl SurfaceQuery, t: &Tuning, dt: f32) {
        let dt = dt.clamp(0.0, 0.05);
        if self.grounded {
            self.step_grounded(input, q, t, dt);
        } else {
            self.step_air(input, q, t, dt);
        }
    }

    fn step_grounded(&mut self, input: &MoveInput, q: &impl SurfaceQuery, t: &Tuning, dt: f32) {
        let r = t.body_radius;
        let contacts = self.probe(q, t);
        let Some(target) = target_normal(&contacts) else {
            self.start_fall();
            self.contacts = contacts;
            return;
        };
        self.target_up = target;
        self.contacts = contacts;

        let wish = self.wish(input);
        let moving = wish.is_some() && self.mode != Mode::ChargeJump;

        // 1. Réalignement de l'up (exponentiel) ; l'avant tourne avec lui (transport parallèle).
        let k = if moving { t.up_interp_walk } else { t.up_interp_idle };
        self.rotate_up_towards(target, 1.0 - (-k * dt).exp());

        // 2. Saut chargé / décrochage (§5).
        if input.jump {
            if self.mode != Mode::ChargeJump {
                self.mode = Mode::ChargeJump;
                self.charge = 0.0;
            }
            self.charge += dt;
            self.velocity = Vec3::ZERO;
            if let Some((dir, _)) = wish {
                self.turn_forward_towards(dir, 1.0 - (-5.0 * dt).exp());
            }
            self.recharge_stamina(t, dt);
            return;
        }
        if self.mode == Mode::ChargeJump {
            let on_steep = self.up.dot(Vec3::Y) < t.drop_cos_threshold;
            if self.charge < t.drop_charge_duration && on_steep {
                self.drop_off(t);
            } else {
                self.launch_jump(wish.map(|(d, _)| d), t);
            }
            return;
        }

        // 3. Vitesse : marche sans inertie, course accélérée avec endurance (§2, §4).
        match wish {
            Some((dir, m)) => {
                let walk = t.walk_speed * m;
                if self.run_locked && self.stamina >= t.stamina_rested {
                    self.run_locked = false;
                }
                let running = input.run && !self.run_locked && self.stamina > 0.0;
                let speed = if running {
                    // part de la vitesse actuelle (0 à l'arrêt : mesuré 0 → 350 u/s en ~0,35 s)
                    let current = self.velocity.length();
                    self.run_speed = (self.run_speed.max(current) + t.run_accel * dt).min(t.run_speed);
                    self.stamina = (self.stamina - t.stamina_use_per_s * dt).max(0.0);
                    if self.stamina <= 0.0 {
                        self.run_locked = true;
                    }
                    self.mode = Mode::Run;
                    self.run_speed
                } else {
                    self.run_speed = 0.0;
                    self.recharge_stamina(t, dt);
                    self.mode = Mode::Walk;
                    walk
                };
                self.velocity = dir * speed;
                self.turn_forward_towards(dir, 1.0 - (-t.forward_interp * dt).exp());
            }
            None => {
                self.velocity = Vec3::ZERO;
                self.run_speed = 0.0;
                self.recharge_stamina(t, dt);
                self.mode = Mode::Idle;
            }
        }

        // 4. Intégration puis résolution contre la surface.
        self.position += self.velocity * dt;
        let max_pull = r * 0.5 + self.velocity.length() * dt * 2.0;
        if !self.resolve_contacts(q, t, max_pull) {
            self.start_fall();
        }
    }

    fn step_air(&mut self, input: &MoveInput, q: &impl SurfaceQuery, t: &Tuning, dt: f32) {
        let r = t.body_radius;
        // Gravité monde et contrôle en l'air limité (§5).
        self.velocity.y = (self.velocity.y - t.gravity * dt).max(-t.max_fall_speed);
        let mut hv = Vec3::new(self.velocity.x, 0.0, self.velocity.z);
        let wish_h = wish_direction(input, Vec3::Y, None).map(|(d, _, m)| (d, m));
        let mut controlled = false;
        if let Some((dir, m)) = wish_h {
            if hv.length() < 1e-3 || hv.angle_between(dir) <= t.max_air_control_angle {
                hv += dir * t.air_control_accel * m * dt;
                controlled = true;
            }
        }
        if !controlled {
            let l = hv.length();
            if l > 0.0 {
                hv *= (l - t.air_h_damping * dt).max(0.0) / l;
            }
        }
        hv = hv.clamp_length_max(t.max_air_h_speed);
        self.velocity.x = hv.x;
        self.velocity.z = hv.z;

        self.rotate_up_towards(Vec3::Y, 1.0 - (-t.air_up_interp * dt).exp());

        // Déplacement balayé (sphère) pour ne pas traverser les surfaces.
        let travel = self.velocity * dt;
        let len = travel.length();
        let mut hit_surface = false;
        if len > 1e-6 {
            let dir = travel / len;
            match q.sphere(self.position, dir, r * 0.95, len) {
                Some(h) => {
                    self.position += dir * (h.distance - r * 0.01).max(0.0);
                    hit_surface = true;
                }
                None => self.position += travel,
            }
        }

        self.jump_timer -= dt;
        if self.jump_timer > 0.0 {
            self.mode = Mode::Jump;
            return;
        }
        self.mode = Mode::Fall;
        let contacts = self.probe(q, t);
        let near = contacts.iter().any(|c| c.point.distance(self.position) <= r + t.ground_skin);
        if near || hit_surface {
            // Atterrissage : on reprend la marche, l'up se réaligne au sol (BaseGroundUpInterpSpeed).
            self.grounded = true;
            self.velocity = Vec3::ZERO;
            self.mode = Mode::Idle;
        }
        self.contacts = contacts;
    }

    /// Repousse le corps hors des surfaces et le ramène contre son support.
    /// Retourne `false` si plus aucune surface n'est assez proche (décroché).
    fn resolve_contacts(&mut self, q: &impl SurfaceQuery, t: &Tuning, max_pull: f32) -> bool {
        let r = t.body_radius;
        let contacts = self.probe(q, t);
        if contacts.is_empty() {
            return false;
        }
        // Pénétration : on pousse depuis le point le plus enfoncé, plusieurs passes (coins).
        for _ in 0..4 {
            let worst = contacts
                .iter()
                .map(|c| (c, c.point.distance(self.position)))
                .min_by(|a, b| a.1.total_cmp(&b.1));
            match worst {
                Some((c, d)) if d < r - 1e-4 => {
                    let away = (self.position - c.point).normalize_or(c.normal);
                    self.position += away * (r - d);
                }
                _ => break,
            }
        }
        // Collage : vers le point de surface le plus proche (sur une arête, c'est l'arête → enroulement).
        let (closest, d) = contacts
            .iter()
            .map(|c| (c, c.point.distance(self.position)))
            .min_by(|a, b| a.1.total_cmp(&b.1))
            .unwrap();
        if d > r * 1.9 {
            return false;
        }
        if d > r {
            let toward = (closest.point - self.position).normalize_or(-self.up);
            self.position += toward * (d - r).min(max_pull);
        }
        true
    }

    fn wish(&mut self, input: &MoveInput) -> Option<(Vec3, f32)> {
        match wish_direction(input, self.up, self.screen_forward) {
            Some((dir, screen_fwd, m)) => {
                self.screen_forward = Some(screen_fwd);
                Some((dir, m))
            }
            None => {
                self.screen_forward = None;
                None
            }
        }
    }

    fn launch_jump(&mut self, wish: Option<Vec3>, t: &Tuning) {
        let frac = (self.charge / t.jump_charge_duration).clamp(0.2, 1.0);
        let fwd = wish.unwrap_or(self.forward);
        let mut dir = (fwd * t.jump_elevation.cos() + self.up * t.jump_elevation.sin()).normalize();
        let from_up = dir.angle_between(Vec3::Y);
        if from_up > t.jump_clamp_from_world_up {
            let axis = dir.cross(Vec3::Y).normalize_or(self.right());
            dir = Quat::from_axis_angle(axis, from_up - t.jump_clamp_from_world_up) * dir;
        }
        self.velocity = dir * t.jump_strength * frac;
        self.stamina = (self.stamina - t.jump_stamina_cost * frac).max(0.0);
        self.grounded = false;
        self.mode = Mode::Jump;
        self.jump_timer = t.jump_exit_duration;
        self.charge = 0.0;
    }

    fn drop_off(&mut self, t: &Tuning) {
        // Lâcher prise : petite impulsion le long de la normale, puis chute.
        self.velocity = self.up * t.body_radius * 3.0;
        self.grounded = false;
        self.mode = Mode::Fall;
        self.jump_timer = t.jump_exit_duration;
        self.charge = 0.0;
    }

    fn start_fall(&mut self) {
        self.grounded = false;
        self.mode = Mode::Fall;
        self.jump_timer = 0.0;
    }

    fn recharge_stamina(&mut self, t: &Tuning, dt: f32) {
        self.stamina = (self.stamina + t.stamina_recharge_per_s * dt).min(1.0);
    }

    fn rotate_up_towards(&mut self, target: Vec3, alpha: f32) {
        let new_up = slerp_dir(self.up, target, alpha, self.forward);
        let rot = Quat::from_rotation_arc(self.up, new_up);
        self.up = new_up;
        self.forward = reproject(rot * self.forward, self.up, self.forward);
    }

    fn turn_forward_towards(&mut self, dir: Vec3, alpha: f32) {
        self.forward = reproject(slerp_dir(self.forward, dir, alpha, self.up), self.up, self.forward);
    }
}

/// Poids d'un contact selon sa distance au centre : 1 jusqu'à R, puis décroissance jusqu'à 0 à 2R.
fn weight(distance: f32, r: f32) -> f32 {
    if distance <= r {
        1.0
    } else {
        (1.0 - (distance - r) / r).max(0.0).powi(2)
    }
}

/// Moyenne pondérée des normales (None si rien d'assez proche).
pub fn target_normal(contacts: &[Contact]) -> Option<Vec3> {
    let sum: Vec3 = contacts.iter().map(|c| c.normal * c.weight).sum();
    let total: f32 = contacts.iter().map(|c| c.weight).sum();
    if total < 0.05 {
        return None;
    }
    sum.try_normalize()
}

/// Direction souhaitée tangente au plan `up`, à partir du stick et du repère caméra (§4).
///
/// « Avant écran » sur la surface = direction tangente dont la projection à l'écran est verticale :
/// `up × droite_caméra`. Son signe est choisi par continuité avec l'image précédente tant que le stick reste
/// poussé (franchissement d'arêtes sans demi-tour), sinon pour pointer vers le haut / le fond de l'écran.
/// Retourne (direction unitaire, avant écran retenu, intensité 0..1).
pub fn wish_direction(input: &MoveInput, up: Vec3, previous: Option<Vec3>) -> Option<(Vec3, Vec3, f32)> {
    let m = input.stick.length().min(1.0);
    if m < STICK_DEADZONE {
        return None;
    }
    let cam_right = input.cam_forward.cross(input.cam_up).normalize_or_zero();
    let mut screen_fwd = up
        .cross(cam_right)
        .try_normalize()
        .filter(|_| up.cross(cam_right).length() > 0.1)
        // surface vue de profil (normale ≈ droite caméra) : le plan contient avant et haut caméra
        .or_else(|| project_on_plane(input.cam_forward + input.cam_up, up).try_normalize())?;
    let flip = match previous {
        Some(prev) => screen_fwd.dot(prev) < 0.0,
        None => screen_fwd.dot(input.cam_up + input.cam_forward) < 0.0,
    };
    if flip {
        screen_fwd = -screen_fwd;
    }
    let screen_right = screen_fwd.cross(up).normalize_or_zero();
    let s = input.stick / input.stick.length();
    let dir = (screen_right * s.x + screen_fwd * s.y).try_normalize()?;
    Some((dir, screen_fwd, m))
}

pub fn project_on_plane(v: Vec3, n: Vec3) -> Vec3 {
    v - n * v.dot(n)
}

fn reproject(v: Vec3, n: Vec3, fallback: Vec3) -> Vec3 {
    project_on_plane(v, n)
        .try_normalize()
        .or_else(|| project_on_plane(fallback, n).try_normalize())
        .unwrap_or_else(|| n.any_orthonormal_vector())
}

/// Interpolation sphérique de directions, avec axe de secours si elles sont opposées.
fn slerp_dir(a: Vec3, b: Vec3, alpha: f32, fallback_axis: Vec3) -> Vec3 {
    let angle = a.angle_between(b);
    if angle < 1e-5 {
        return b;
    }
    let axis = a.cross(b).try_normalize().unwrap_or_else(|| {
        project_on_plane(fallback_axis, a).try_normalize().unwrap_or_else(|| a.any_orthonormal_vector())
    });
    (Quat::from_axis_angle(axis, angle * alpha.clamp(0.0, 1.0)) * a).normalize()
}
