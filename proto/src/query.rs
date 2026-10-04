//! Requêtes de scène utilisées par le marcheur et la caméra.
//!
//! La logique (walker, caméra) ne dépend que de ce trait : en jeu il est implémenté par Avian
//! (`game::AvianQuery`), dans les tests par [`BoxWorld`], un monde de boîtes alignées analytique.

use bevy::math::Vec3;

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Hit {
    pub distance: f32,
    /// Normale de la surface touchée (monde, unitaire).
    pub normal: Vec3,
}

pub trait SurfaceQuery {
    /// Rayon depuis `origin` dans la direction unitaire `dir`.
    fn ray(&self, origin: Vec3, dir: Vec3, max_distance: f32) -> Option<Hit>;
    /// Sphère de rayon `radius` lancée depuis `origin` dans la direction unitaire `dir`.
    fn sphere(&self, origin: Vec3, dir: Vec3, radius: f32, max_distance: f32) -> Option<Hit>;
}

/// Boîte alignée sur les axes (min, max).
#[derive(Clone, Copy, Debug)]
pub struct Aabb {
    pub min: Vec3,
    pub max: Vec3,
}

impl Aabb {
    pub fn from_center_size(center: Vec3, size: Vec3) -> Self {
        Self { min: center - size * 0.5, max: center + size * 0.5 }
    }

    fn inflated(&self, r: f32) -> Self {
        Self { min: self.min - Vec3::splat(r), max: self.max + Vec3::splat(r) }
    }

    /// Intersection rayon / boîte (méthode des dalles). Ignore les rayons partant de l'intérieur.
    fn ray(&self, origin: Vec3, dir: Vec3, max_distance: f32) -> Option<Hit> {
        let mut t_enter = f32::NEG_INFINITY;
        let mut t_exit = f32::INFINITY;
        let mut normal = Vec3::ZERO;
        for axis in 0..3 {
            let o = origin[axis];
            let d = dir[axis];
            let (lo, hi) = (self.min[axis], self.max[axis]);
            if d.abs() < 1e-8 {
                if o < lo || o > hi {
                    return None;
                }
                continue;
            }
            let (mut t0, mut t1) = ((lo - o) / d, (hi - o) / d);
            let mut n = Vec3::ZERO;
            n[axis] = -d.signum();
            if t0 > t1 {
                std::mem::swap(&mut t0, &mut t1);
            }
            if t0 > t_enter {
                t_enter = t0;
                normal = n;
            }
            t_exit = t_exit.min(t1);
            if t_enter > t_exit {
                return None;
            }
        }
        if t_enter < 0.0 || t_enter > max_distance {
            return None;
        }
        Some(Hit { distance: t_enter, normal })
    }
}

/// Monde de test : un ensemble de boîtes statiques.
#[derive(Clone, Debug, Default)]
pub struct BoxWorld {
    pub boxes: Vec<Aabb>,
}

impl BoxWorld {
    pub fn with(mut self, center: Vec3, size: Vec3) -> Self {
        self.boxes.push(Aabb::from_center_size(center, size));
        self
    }
}

fn closest(hits: impl Iterator<Item = Hit>) -> Option<Hit> {
    hits.min_by(|a, b| a.distance.total_cmp(&b.distance))
}

impl SurfaceQuery for BoxWorld {
    fn ray(&self, origin: Vec3, dir: Vec3, max_distance: f32) -> Option<Hit> {
        closest(self.boxes.iter().filter_map(|b| b.ray(origin, dir, max_distance)))
    }

    /// Approximation : rayon contre les boîtes gonflées du rayon (coins carrés). Suffisant pour les tests.
    fn sphere(&self, origin: Vec3, dir: Vec3, radius: f32, max_distance: f32) -> Option<Hit> {
        closest(self.boxes.iter().filter_map(|b| b.inflated(radius).ray(origin, dir, max_distance)))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ray_hits_floor_from_above() {
        let w = BoxWorld::default().with(Vec3::new(0.0, -5.0, 0.0), Vec3::new(100.0, 10.0, 100.0));
        let h = w.ray(Vec3::new(0.0, 14.0, 0.0), Vec3::NEG_Y, 100.0).unwrap();
        assert!((h.distance - 14.0).abs() < 1e-4);
        assert_eq!(h.normal, Vec3::Y);
        assert!(w.ray(Vec3::new(0.0, 14.0, 0.0), Vec3::Y, 100.0).is_none());
    }

    #[test]
    fn ray_hits_wall_side() {
        let w = BoxWorld::default().with(Vec3::new(50.0, 50.0, 0.0), Vec3::new(10.0, 100.0, 100.0));
        let h = w.ray(Vec3::new(0.0, 10.0, 0.0), Vec3::X, 100.0).unwrap();
        assert!((h.distance - 45.0).abs() < 1e-4);
        assert_eq!(h.normal, Vec3::NEG_X);
    }
}
