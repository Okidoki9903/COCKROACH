//! Prototype COCKROACH : caméra à hauteur d'insecte et marche multi-surfaces.
//!
//! La logique est indépendante de Bevy (hors types mathématiques) et testée contre un monde de boîtes
//! analytique ; `main.rs` la branche sur Bevy + Avian.

pub mod camera_rig;
pub mod query;
pub mod tuning;
pub mod walker;

#[cfg(test)]
mod spec_tests;
