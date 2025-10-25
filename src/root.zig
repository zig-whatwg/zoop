//! Zoop - Zero-cost OOP for Zig
//!
//! Zoop provides automatic code generation for object-oriented programming
//! in Zig, with zero runtime overhead and configurable method prefixes.
//!
//! ## Usage
//!
//! In your source code, use `zoop.class()` to mark structs for code generation:
//!
//! ```zig
//! const zoop = @import("zoop");
//!
//! pub const Animal = zoop.class(struct {
//!     name: []const u8,
//!     pub fn makeSound(self: *Animal) void { ... }
//! });
//!
//! pub const Dog = zoop.class(struct {
//!     pub const extends = Animal;
//!     breed: []const u8,
//! });
//! ```
//!
//! In your build.zig, integrate the zoop-codegen tool. See README for details.

const std = @import("std");

/// Class definition function
/// Wrap your struct with this to enable inheritance and code generation
pub const class = @import("class.zig").class;

/// Configuration for generated method names
pub const ClassConfig = @import("class.zig").ClassConfig;
