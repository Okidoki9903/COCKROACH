//! Tests d'acceptation : le prototype doit reproduire les chiffres mesurés sur Les Fourmis
//! (docs/specs/*.md §« Critères »). Unités du jeu mesuré (corps R = 14 u), monde Bevy (+Y en haut).

use std::f32::consts::FRAC_PI_2;

use bevy::math::{Vec2, Vec3};

use crate::camera_rig::CameraRig;
use crate::query::BoxWorld;
use crate::tuning::Tuning;
use crate::walker::{Mode, MoveInput, Walker};

const DT: f32 = 1.0 / 60.0;

#[derive(Clone, Copy, Debug)]
struct Sample {
    t: f32,
    pos: Vec3,
    up: Vec3,
    mode: Mode,
    grounded: bool,
}

fn floor() -> BoxWorld {
    BoxWorld::default().with(Vec3::new(0.0, -50.0, 0.0), Vec3::new(8000.0, 100.0, 8000.0))
}

/// Caméra horizontale qui regarde vers +X.
fn input(stick: Vec2) -> MoveInput {
    MoveInput { stick, cam_forward: Vec3::X, cam_up: Vec3::Y, ..Default::default() }
}

fn simulate(w: &mut Walker, inp: MoveInput, q: &BoxWorld, t: &Tuning, secs: f32, t0: f32) -> Vec<Sample> {
    let n = (secs / DT).round() as usize;
    (1..=n)
        .map(|i| {
            w.step(&inp, q, t, DT);
            Sample { t: t0 + i as f32 * DT, pos: w.position, up: w.up, mode: w.mode, grounded: w.grounded }
        })
        .collect()
}

fn speed_between(s: &[Sample], a: usize, b: usize) -> f32 {
    s[a].pos.distance(s[b].pos) / (s[b].t - s[a].t)
}

// ------------------------------------------------------------------ vitesses (surface-movement §2)

#[test]
fn walk_full_stick_is_180_and_instant() {
    let t = Tuning::ant();
    let q = floor();
    let mut w = Walker::new(Vec3::new(0.0, 14.0, 0.0), Vec3::X);
    let s = simulate(&mut w, input(Vec2::Y), &q, &t, 1.0, 0.0);
    let v = speed_between(&s, 30, 59);
    assert!((v - 180.0).abs() < 1.0, "vitesse marche {v}");
    // ≤ 0,05 s pour atteindre la croisière : dès la 2e image
    let v_early = speed_between(&s, 1, 3);
    assert!((v_early - 180.0).abs() < 2.0, "accélération marche {v_early}");
    assert!((s[59].pos.y - 14.0).abs() < 0.2, "reste posé : y = {}", s[59].pos.y);
    // arrêt en une image
    let before = w.position;
    let s2 = simulate(&mut w, input(Vec2::ZERO), &q, &t, DT, 1.0);
    assert!(s2[0].pos.distance(before) < 1e-3);
    assert_eq!(s2[0].mode, Mode::Idle);
}

#[test]
fn walk_speed_proportional_to_stick() {
    let t = Tuning::ant();
    let q = floor();
    let mut w = Walker::new(Vec3::new(0.0, 14.0, 0.0), Vec3::X);
    // vitesse ∝ inclinaison au-delà de la zone morte (remise à l'échelle)
    let s = simulate(&mut w, input(Vec2::new(0.0, 0.6)), &q, &t, 1.0, 0.0);
    let v = speed_between(&s, 30, 59);
    assert!((v - 90.0).abs() < 1.0, "vitesse stick 0,6 → mi-vitesse : {v}");
    let mut w = Walker::new(Vec3::new(0.0, 14.0, 0.0), Vec3::X);
    let s = simulate(&mut w, input(Vec2::new(0.0, 0.15)), &q, &t, 0.5, 0.0);
    assert!(s.last().unwrap().pos.distance(Vec3::new(0.0, 14.0, 0.0)) < 1e-3, "dérive du stick ignorée");
}

#[test]
fn run_accelerates_to_700() {
    let t = Tuning::ant();
    let q = floor();
    let mut w = Walker::new(Vec3::new(0.0, 14.0, 0.0), Vec3::X);
    let inp = MoveInput { run: true, ..input(Vec2::Y) };
    let s = simulate(&mut w, inp, &q, &t, 1.5, 0.0);
    let v035 = speed_between(&s, 19, 21);
    println!("[mesure] course : {v035:.0} u/s à 0,35 s");
    assert!((300.0..=400.0).contains(&v035), "course à 0,35 s : {v035}");
    let v_end = speed_between(&s, 70, 89);
    assert!((v_end - 700.0).abs() < 2.0, "course établie {v_end}");
    assert!(s.iter().skip(1).all(|x| x.mode == Mode::Run));
}

// ------------------------------------------------------------------ surfaces (surface-movement §3)

fn up_angle_deg(up: Vec3, reference: Vec3) -> f32 {
    up.angle_between(reference).to_degrees()
}

/// Sol + mur (face à x = 300, normale -X).
fn floor_and_wall() -> BoxWorld {
    floor().with(Vec3::new(350.0, 500.0, 0.0), Vec3::new(100.0, 1000.0, 8000.0))
}

#[test]
fn floor_to_wall_transition_takes_about_0_2_s() {
    let t = Tuning::ant();
    let q = floor_and_wall();
    let mut w = Walker::new(Vec3::new(200.0, 14.0, 0.0), Vec3::X);
    // ~100 u/s comme dans la mesure (cas 5)
    let s = simulate(&mut w, input(Vec2::new(0.0, 0.2 + 0.8 * 100.0 / 180.0)), &q, &t, 3.0, 0.0);
    let t10 = s.iter().find(|x| up_angle_deg(x.up, Vec3::Y) >= 10.0).expect("ne bascule jamais").t;
    let t80 = s.iter().find(|x| up_angle_deg(x.up, Vec3::Y) >= 80.0).expect("n'atteint jamais le mur").t;
    let dur = t80 - t10;
    println!("[mesure] bascule sol→mur 10°→80° : {dur:.3} s (Les Fourmis : 0,15-0,25 s)");
    assert!((0.08..=0.35).contains(&dur), "durée de bascule 10°→80° : {dur:.3} s (mesuré 0,15-0,25 s)");
    let last = s.last().unwrap();
    assert!(s.iter().all(|x| x.grounded), "ne doit jamais décrocher");
    assert!(up_angle_deg(last.up, Vec3::NEG_X) < 15.0, "up final {:?}", last.up);
    assert!(last.pos.y > 100.0, "doit monter le mur : y = {}", last.pos.y);
    assert!((last.pos.x - 286.0).abs() < 3.0, "collé au mur à R : x = {}", last.pos.x);
}

#[test]
fn wall_to_ceiling_and_walk_upside_down() {
    let t = Tuning::ant();
    let q = floor_and_wall().with(Vec3::new(0.0, 650.0, 0.0), Vec3::new(8000.0, 100.0, 8000.0));
    let mut w = Walker::new(Vec3::new(200.0, 14.0, 0.0), Vec3::X);
    let inp = input(Vec2::Y);
    let s = simulate(&mut w, inp, &q, &t, 6.0, 0.0);
    assert!(s.iter().all(|x| x.grounded), "ne doit jamais décrocher (sol → mur → plafond)");
    let i = s.iter().position(|x| x.up.dot(Vec3::NEG_Y) > 0.95).expect("n'atteint jamais le plafond");
    // en gardant le stick poussé, la continuité fait repartir le long du plafond, tête en bas
    let x_on_ceiling = s[i].pos.x;
    println!("[mesure] plafond atteint à t = {:.2} s", s[i].t);
    let after = simulate(&mut w, inp, &q, &t, 1.0, s.last().unwrap().t);
    let last = after.last().unwrap();
    assert!(after.iter().all(|x| x.grounded));
    assert!(last.up.dot(Vec3::NEG_Y) > 0.95, "toujours au plafond : up {:?}", last.up);
    assert!((last.pos.y - 586.0).abs() < 3.0, "collé au plafond : y = {}", last.pos.y);
    assert!(last.pos.x < x_on_ceiling - 150.0, "avance au plafond à pleine vitesse : x {} → {}", x_on_ceiling, last.pos.x);
}

#[test]
fn convex_edge_wraps_onto_side_face() {
    let t = Tuning::ant();
    // dessus de table à y = 200, arête à x = 200, face latérale normale +X
    let q = floor().with(Vec3::new(0.0, 100.0, 0.0), Vec3::new(400.0, 200.0, 400.0));
    let mut w = Walker::new(Vec3::new(150.0, 214.0, 0.0), Vec3::X);
    let s = simulate(&mut w, input(Vec2::new(0.0, 0.2 + 0.8 * 100.0 / 180.0)), &q, &t, 2.0, 0.0);
    assert!(s.iter().all(|x| x.grounded), "ne doit pas tomber de l'arête");
    let last = s.last().unwrap();
    assert!(up_angle_deg(last.up, Vec3::X) < 20.0, "s'enroule sur la face : up {:?}", last.up);
    assert!(last.pos.y < 190.0, "descend la face : y = {}", last.pos.y);
    assert!((last.pos.x - 214.0).abs() < 3.0, "collé à la face : x = {}", last.pos.x);
    // arc d'enroulement ≈ R : la rotation de 90° se fait sur ~1,5-3 R de trajet
    let a = s.iter().find(|x| up_angle_deg(x.up, Vec3::Y) >= 10.0).unwrap();
    let b = s.iter().find(|x| up_angle_deg(x.up, Vec3::Y) >= 80.0).unwrap();
    let path: f32 = s.windows(2).filter(|p| p[0].t >= a.t && p[1].t <= b.t).map(|p| p[0].pos.distance(p[1].pos)).sum();
    println!("[mesure] trajet pendant l'enroulement d'arête : {path:.1} u (≈ {:.2} R)", path / 14.0);
    assert!((5.0..=45.0).contains(&path), "trajet pendant l'enroulement : {path:.1} u");
}

#[test]
fn stick_up_climbs_wall_facing_away_from_camera() {
    // cas 6 : sur une face tournée à l'opposé de la caméra, un nouvel appui « haut » fait monter
    let t = Tuning::ant();
    let q = floor().with(Vec3::new(250.0, 500.0, 0.0), Vec3::new(100.0, 1000.0, 8000.0));
    let mut w = Walker::new(Vec3::new(314.0, 300.0, 0.0), Vec3::Y);
    w.up = Vec3::X;
    w.forward = Vec3::Y;
    let s = simulate(&mut w, input(Vec2::Y), &q, &t, 0.5, 0.0);
    assert!(s.iter().all(|x| x.grounded));
    assert!(s.last().unwrap().pos.y > 360.0, "doit monter : y = {}", s.last().unwrap().pos.y);
}

// ------------------------------------------------------------------ air (surface-movement §5)

#[test]
fn full_charge_jump_launch_and_gravity() {
    let t = Tuning::ant();
    let q = floor();
    let mut w = Walker::new(Vec3::new(0.0, 14.0, 0.0), Vec3::X);
    let hold = MoveInput { jump: true, ..input(Vec2::ZERO) };
    let s = simulate(&mut w, hold, &q, &t, 0.6, 0.0);
    assert!(s.iter().all(|x| x.mode == Mode::ChargeJump));
    assert!(s.last().unwrap().pos.distance(Vec3::new(0.0, 14.0, 0.0)) < 0.5, "immobile pendant la charge");
    let s = simulate(&mut w, input(Vec2::ZERO), &q, &t, DT, 0.6);
    assert_eq!(s[0].mode, Mode::Jump);
    let v = w.velocity;
    assert!((v.length() - 700.0).abs() < 25.0, "vitesse de départ {}", v.length());
    let elev = v.y.atan2(Vec3::new(v.x, 0.0, v.z).length()).to_degrees();
    println!("[mesure] saut : {:.0} u/s à {elev:.1}°", v.length());
    assert!((elev - 34.0).abs() < 2.0, "angle de départ {elev:.1}° (mesuré 30-38°)");
    // gravité : vy(t) linéaire de pente -980
    let vy0 = w.velocity.y;
    simulate(&mut w, input(Vec2::ZERO), &q, &t, 0.3, 0.6);
    let g = (vy0 - w.velocity.y) / 0.3;
    assert!((g - 980.0).abs() < 10.0, "gravité {g}");
    // retombe et se repose
    let s = simulate(&mut w, input(Vec2::ZERO), &q, &t, 2.0, 0.9);
    assert!(s.last().unwrap().grounded, "doit atterrir");
    assert!((s.last().unwrap().pos.y - 14.0).abs() < 2.0, "posé au sol : y = {}", s.last().unwrap().pos.y);
}

#[test]
fn tap_jump_on_ceiling_drops_off() {
    let t = Tuning::ant();
    let q = floor().with(Vec3::new(0.0, 650.0, 0.0), Vec3::new(8000.0, 100.0, 8000.0));
    let mut w = Walker::new(Vec3::new(0.0, 586.0, 0.0), Vec3::X);
    w.up = Vec3::NEG_Y;
    simulate(&mut w, input(Vec2::ZERO), &q, &t, 0.2, 0.0);
    assert!(w.grounded && w.up.dot(Vec3::NEG_Y) > 0.99, "tient au plafond");
    simulate(&mut w, MoveInput { jump: true, ..input(Vec2::ZERO) }, &q, &t, DT * 3.0, 0.2);
    simulate(&mut w, input(Vec2::ZERO), &q, &t, DT, 0.25);
    assert!(!w.grounded, "doit lâcher prise");
    let s = simulate(&mut w, input(Vec2::ZERO), &q, &t, 3.0, 0.27);
    let last = s.last().unwrap();
    assert!(last.grounded && last.pos.y < 30.0, "retombe au sol : {:?}", last.pos);
    assert!(last.up.dot(Vec3::Y) > 0.95, "se remet à l'endroit : up {:?}", last.up);
}

// ------------------------------------------------------------------ caméra (camera.md §7)

fn rig_looking_plus_x(pitch_deg: f32) -> CameraRig {
    CameraRig::new(-FRAC_PI_2, pitch_deg.to_radians())
}

#[test]
fn camera_rest_geometry() {
    let t = Tuning::ant();
    let q = floor();
    let mut rig = rig_looking_plus_x(-2.47);
    let body = Vec3::new(0.0, 14.0, 0.0);
    let mut out = rig.update(body, Vec3::Y, false, &q, &t, DT);
    for _ in 0..60 {
        out = rig.update(body, Vec3::Y, false, &q, &t, DT);
    }
    assert!((out.distance - 300.0).abs() < 0.01, "bras {}", out.distance);
    assert!((out.position.y - body.y - 32.93).abs() < 0.1, "hauteur {}", out.position.y - body.y);
    assert!(rig.forward().distance(Vec3::new(0.999, -0.043, 0.0)) < 0.01);
}

#[test]
fn camera_rotation_rate_and_pitch_clamp() {
    let t = Tuning::ant();
    let mut rig = rig_looking_plus_x(0.0);
    let yaw0 = rig.yaw;
    for _ in 0..60 {
        rig.rotate(Vec2::X, Vec2::ZERO, &t, DT);
    }
    assert!(((yaw0 - rig.yaw).to_degrees() - 180.0).abs() < 0.5, "180 °/s");
    for _ in 0..120 {
        rig.rotate(Vec2::Y, Vec2::ZERO, &t, DT);
    }
    assert!((rig.pitch.to_degrees() - 86.0).abs() < 1e-3, "pitch max {}", rig.pitch.to_degrees());
    for _ in 0..240 {
        rig.rotate(Vec2::NEG_Y, Vec2::ZERO, &t, DT);
    }
    assert!((rig.pitch.to_degrees() + 86.0).abs() < 1e-3);
    // diagonale : norme de la vitesse angulaire = 180 °/s
    let (y0, p0) = (rig.yaw, 0.0f32);
    rig.pitch = 0.0;
    rig.rotate(Vec2::new(1.0, 1.0).normalize(), Vec2::ZERO, &t, DT);
    let w = Vec2::new(rig.yaw - y0, rig.pitch - p0).length().to_degrees() / DT;
    assert!((w - 180.0).abs() < 0.5, "diagonale {w}");
}

/// Corps qui s'éloigne de la caméra en ligne droite à vitesse `v` : excès de distance en régime établi.
fn steady_leash_excess(v: f32, running: bool) -> f32 {
    let t = Tuning::ant();
    let q = BoxWorld::default();
    let mut rig = rig_looking_plus_x(0.0);
    let mut out = None;
    for i in 0..(4.0 / DT) as usize {
        let body = Vec3::new(v * i as f32 * DT, 14.0, 0.0);
        out = Some(rig.update(body, Vec3::Y, running, &q, &t, DT));
    }
    out.unwrap().distance - 300.0
}

#[test]
fn camera_leash_matches_measurements() {
    let e53 = steady_leash_excess(53.0, false);
    println!("[mesure] laisse : +{e53:.1} u à 53 u/s, +{:.1} à 180, +{:.1} en course (Les Fourmis : 10,9 / 25,7 / 65-73)", steady_leash_excess(180.0, false), steady_leash_excess(700.0, true));
    assert!((e53 - 10.9).abs() < 2.0, "excès à 53 u/s : {e53:.1} (mesuré 10,9)");
    let e180 = steady_leash_excess(180.0, false);
    assert!((e180 - 25.7).abs() < 3.0, "excès à 180 u/s : {e180:.1} (mesuré 25,7)");
    let e700 = steady_leash_excess(700.0, true);
    assert!((60.0..=80.0).contains(&e700), "excès en course : {e700:.1} (mesuré 65-73)");
}

#[test]
fn camera_leash_returns_after_stop() {
    let t = Tuning::ant();
    let q = BoxWorld::default();
    let mut rig = rig_looking_plus_x(0.0);
    let mut x = 0.0;
    for _ in 0..(3.0 / DT) as usize {
        x += 53.0 * DT;
        rig.update(Vec3::new(x, 14.0, 0.0), Vec3::Y, false, &q, &t, DT);
    }
    let mut d = 0.0;
    for _ in 0..(1.0 / DT) as usize {
        d = rig.update(Vec3::new(x, 14.0, 0.0), Vec3::Y, false, &q, &t, DT).distance - 300.0;
    }
    assert!(d < 1.0, "retour en ~1 s : excès restant {d:.2}");
}

#[test]
fn camera_collides_with_floor_then_zooms_out_at_200() {
    let t = Tuning::ant();
    let q = floor();
    let body = Vec3::new(0.0, 14.0, 0.0);
    let mut rig = rig_looking_plus_x(60.0); // regarde vers le haut : la caméra passerait sous le sol
    let mut out = rig.update(body, Vec3::Y, false, &q, &t, DT);
    assert!(out.position.y >= t.cam_sphere_radius - 0.01, "ne traverse pas le sol : y = {}", out.position.y);
    assert!(out.distance < 50.0, "rentrée instantanée : {}", out.distance);
    let d0 = out.distance;
    rig.pitch = (-10f32).to_radians();
    out = rig.update(body, Vec3::Y, false, &q, &t, DT);
    let d1 = out.distance;
    for _ in 0..30 {
        out = rig.update(body, Vec3::Y, false, &q, &t, DT);
    }
    let rate = (out.distance - d1) / (30.0 * DT);
    assert!((rate - 200.0).abs() < 1.0, "ressortie {rate:.1} u/s (d0 = {d0:.1})");
}

#[test]
fn camera_ignores_body_orientation() {
    let t = Tuning::ant();
    let q = BoxWorld::default();
    let mut rig = rig_looking_plus_x(-10.0);
    let a = rig.update(Vec3::ZERO, Vec3::Y, false, &q, &t, DT).rotation;
    let b = rig.update(Vec3::ZERO, Vec3::NEG_X, false, &q, &t, DT).rotation;
    assert!(a.angle_between(b) < 1e-6, "la caméra ne tourne pas avec la surface");
    assert!((b * Vec3::X).y.abs() < 1e-6, "roll nul");
}
