//! # Code Generation Engine for Zoop
//!
//! This module implements the core code generation logic for Zoop. It scans
//! Zig source files, parses class definitions, resolves cross-file inheritance,
//! and generates enhanced code with method wrappers and property accessors.
//!
//! ## Architecture
//!
//! The code generator operates in two passes:
//!
//! ### Pass 1: Scan and Build Registry
//!
//! 1. Walk all `.zig` files in source directory
//! 2. Parse each file to find `zoop.class()` calls
//! 3. Extract class definitions, parent classes, and imports
//! 4. Build a global registry of all classes and their relationships
//! 5. Detect circular inheritance
//!
//! ### Pass 2: Generate Code
//!
//! 1. For each file with classes:
//!    - Generate enhanced struct definitions
//!    - Add `super: ParentType` field for inherited classes
//!    - Generate property getter/setter methods
//!    - Generate method wrappers for inherited methods (unless overridden)
//! 2. Write generated files to output directory (preserving structure)
//!
//! ## Cross-File Inheritance
//!
//! When a child class extends a parent from another file:
//!
//! ```zig
//! // file1.zig
//! const base = @import("base.zig");
//! const Child = zoop.class(struct {
//!     pub const extends = base.Parent,
//! });
//! ```
//!
//! The generator:
//! 1. Parses the `@import("base.zig")` statement
//! 2. Resolves the relative path to find `base.zig`
//! 3. Looks up `Parent` class in the global registry
//! 4. Generates wrappers for `Parent`'s methods in `Child`
//!
//! ## Security
//!
//! - Path validation prevents traversal attacks (`..` blocked)
//! - Memory-safe: all allocations properly freed, `errdefer` on error paths
//! - No unsafe pointer casts
//!
//! ## Public API
//!
//! - `generateAllClasses()` - Main entry point for code generation
//! - `ClassConfig` - Configuration for method/property prefixes
//!
//! ## Implementation Details
//!
//! See IMPLEMENTATION.md for detailed architecture documentation.

const std = @import("std");

/// Configuration for generated class method prefixes.
///
/// Controls the naming of generated wrapper methods and property accessors.
/// These settings are typically passed via command-line arguments to zoop-codegen.
///
/// See src/root.zig or src/class.zig for detailed documentation on usage.
pub const ClassConfig = struct {
    method_prefix: []const u8 = "call_",
    getter_prefix: []const u8 = "get_",
    setter_prefix: []const u8 = "set_",
};

/// Class generation specification
pub const ClassSpec = struct {
    name: []const u8,
    parent: ?type = null,
    definition: type,
    config: ClassConfig = .{},
};

/// Validate that a file path doesn't contain path traversal attempts
fn isPathSafe(path: []const u8) bool {
    // Check for absolute paths
    if (path.len > 0 and path[0] == '/') return false;

    // Check for Windows absolute paths (C:, D:, etc.)
    if (path.len >= 2 and path[1] == ':') return false;

    // Check for parent directory references
    if (std.mem.indexOf(u8, path, "..") != null) return false;

    // Check for backslashes (Windows path separator, could be used for traversal)
    if (std.mem.indexOf(u8, path, "\\") != null) return false;

    return true;
}

/// Main entry point: Generate all classes in source directory
pub fn generateAllClasses(
    allocator: std.mem.Allocator,
    source_dir: []const u8,
    output_dir: []const u8,
    config: ClassConfig,
) !void {
    // Create output directory
    std.fs.cwd().makePath(output_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };

    // Initialize global registry
    var registry = GlobalRegistry.init(allocator);
    defer registry.deinit();

    // PASS 1: Scan all files and build global registry
    var source_dir_handle = try std.fs.cwd().openDir(source_dir, .{ .iterate = true });
    defer source_dir_handle.close();

    var walker = try source_dir_handle.walk(allocator);
    defer walker.deinit();

    var files_processed: usize = 0;

    while (try walker.next()) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.path, ".zig")) continue;

        // Validate path for security
        if (!isPathSafe(entry.path)) {
            std.debug.print("Warning: Skipping file with unsafe path: {s}\n", .{entry.path});
            continue;
        }

        files_processed += 1;

        const source_path = try std.fs.path.join(allocator, &.{ source_dir, entry.path });
        defer allocator.free(source_path);

        const source_content = try std.fs.cwd().readFileAlloc(
            allocator,
            source_path,
            10 * 1024 * 1024,
        );
        errdefer allocator.free(source_content);

        if (std.mem.indexOf(u8, source_content, "zoop.class(") != null or
            std.mem.indexOf(u8, source_content, "@import(\"zoop\")") != null)
        {
            const file_path_owned = try allocator.dupe(u8, entry.path);
            errdefer allocator.free(file_path_owned);

            var file_info = FileInfo{
                .path = file_path_owned,
                .imports = std.StringHashMap([]const u8).init(allocator),
                .classes = std.ArrayList(ClassInfo){},
                .source_content = source_content,
            };
            file_info.classes = .empty;

            try parseImports(allocator, source_content, file_path_owned, &file_info.imports);
            try scanFileForClasses(allocator, source_content, file_path_owned, &file_info.classes);

            try registry.files.put(file_path_owned, file_info);
        } else {
            allocator.free(source_content);
        }
    }

    // Check for circular inheritance across all files
    var global_file_it = registry.files.iterator();
    while (global_file_it.next()) |entry| {
        const file_path = entry.key_ptr.*;
        const file_info = entry.value_ptr.*;

        for (file_info.classes.items) |class_info| {
            var visited = std.StringHashMap(void).init(allocator);
            defer visited.deinit();

            try detectCircularInheritanceGlobal(
                class_info.name,
                class_info.parent_name,
                file_path,
                &registry,
                &visited,
            );
        }
    }

    // PASS 2: Generate code for each file
    var classes_generated: usize = 0;
    var file_it = registry.files.iterator();

    while (file_it.next()) |entry| {
        const file_path = entry.key_ptr.*;
        const file_info = entry.value_ptr.*;

        // Validate path again before writing (defense in depth)
        if (!isPathSafe(file_path)) {
            std.debug.print("Error: Refusing to write file with unsafe path: {s}\n", .{file_path});
            return error.UnsafePath;
        }

        const generated = try processSourceFileWithRegistry(
            allocator,
            file_info.source_content,
            file_path,
            &registry,
            config,
        );
        defer allocator.free(generated);

        const output_path = try std.fs.path.join(allocator, &.{ output_dir, file_path });
        defer allocator.free(output_path);

        if (std.fs.path.dirname(output_path)) |parent_dir| {
            std.fs.cwd().makePath(parent_dir) catch |err| switch (err) {
                error.PathAlreadyExists => {},
                else => return err,
            };
        }

        const output_file = try std.fs.cwd().createFile(output_path, .{});
        defer output_file.close();

        try output_file.writeAll(generated);

        classes_generated += 1;
        std.debug.print("  Generated: {s}\n", .{file_path});
    }

    std.debug.print("\nProcessed {} files, generated {} class files\n", .{ files_processed, classes_generated });
}

/// Parsed method definition
const MethodDef = struct {
    name: []const u8,
    source: []const u8,
    signature: []const u8,
    return_type: []const u8,
    is_static: bool = false,
};

/// Parsed field definition
const FieldDef = struct {
    name: []const u8,
    type_name: []const u8,
    default_value: ?[]const u8,
    estimated_size: usize = 0,
};

/// Property access mode
const PropertyAccess = enum {
    read_only,
    read_write,
};

/// Parsed property definition
const PropertyDef = struct {
    name: []const u8,
    type_name: []const u8,
    access: PropertyAccess,
    default_value: ?[]const u8,
};

/// Parsed class definition
const ParsedClass = struct {
    name: []const u8,
    parent_name: ?[]const u8,
    mixin_names: [][]const u8,
    fields: []FieldDef,
    methods: []MethodDef,
    properties: []PropertyDef,
    allocator: std.mem.Allocator,

    fn deinit(self: *ParsedClass) void {
        for (self.mixin_names) |mixin_name| {
            self.allocator.free(mixin_name);
        }
        self.allocator.free(self.mixin_names);
        self.allocator.free(self.fields);
        self.allocator.free(self.methods);
        self.allocator.free(self.properties);
    }
};

const ClassInfo = struct {
    name: []const u8,
    parent_name: ?[]const u8,
    mixin_names: [][]const u8, // List of mixin class references
    fields: []FieldDef,
    methods: []MethodDef,
    properties: []PropertyDef,
    source_start: usize,
    source_end: usize,
    file_path: []const u8,
};

const FileInfo = struct {
    path: []const u8,
    imports: std.StringHashMap([]const u8),
    classes: std.ArrayListUnmanaged(ClassInfo),
    source_content: []const u8,
};

const GlobalRegistry = struct {
    allocator: std.mem.Allocator,
    files: std.StringHashMap(FileInfo),

    fn init(allocator: std.mem.Allocator) GlobalRegistry {
        return .{
            .allocator = allocator,
            .files = std.StringHashMap(FileInfo).init(allocator),
        };
    }

    fn deinit(self: *GlobalRegistry) void {
        var it = self.files.iterator();
        while (it.next()) |entry| {
            var import_it = entry.value_ptr.imports.iterator();
            while (import_it.next()) |import_entry| {
                self.allocator.free(import_entry.key_ptr.*);
                self.allocator.free(import_entry.value_ptr.*);
            }
            entry.value_ptr.imports.deinit();

            for (entry.value_ptr.classes.items) |class_info| {
                for (class_info.mixin_names) |mixin_name| {
                    self.allocator.free(mixin_name);
                }
                self.allocator.free(class_info.mixin_names);
                self.allocator.free(class_info.fields);
                self.allocator.free(class_info.methods);
                self.allocator.free(class_info.properties);
            }
            entry.value_ptr.classes.deinit(self.allocator);
            self.allocator.free(entry.value_ptr.source_content);
            self.allocator.free(entry.value_ptr.path);
        }
        self.files.deinit();
    }

    fn addClass(self: *GlobalRegistry, file_path: []const u8, class_info: ClassInfo) !void {
        const file_info = self.files.getPtr(file_path) orelse return error.FileNotFound;
        try file_info.classes.append(class_info);
    }

    fn getClass(self: *GlobalRegistry, file_path: []const u8, class_name: []const u8) ?ClassInfo {
        const file_info = self.files.get(file_path) orelse return null;
        for (file_info.classes.items) |class_info| {
            if (std.mem.eql(u8, class_info.name, class_name)) {
                return class_info;
            }
        }
        return null;
    }

    fn resolveParentReference(
        self: *GlobalRegistry,
        parent_ref: []const u8,
        current_file: []const u8,
    ) !?ClassInfo {
        const dot_pos = std.mem.indexOfScalar(u8, parent_ref, '.');

        if (dot_pos) |pos| {
            const import_alias = parent_ref[0..pos];
            const class_name = parent_ref[pos + 1 ..];

            const file_info = self.files.get(current_file) orelse return error.FileNotFound;
            const imported_file = file_info.imports.get(import_alias) orelse {
                return null;
            };

            return self.getClass(imported_file, class_name);
        } else {
            return self.getClass(current_file, parent_ref);
        }
    }
};

fn parseImports(
    allocator: std.mem.Allocator,
    source: []const u8,
    current_file: []const u8,
    imports: *std.StringHashMap([]const u8),
) !void {
    var pos: usize = 0;

    while (pos < source.len) {
        const import_pos = std.mem.indexOfPos(u8, source, pos, "@import(") orelse break;

        const quote_start = std.mem.indexOfPos(u8, source, import_pos, "\"") orelse {
            pos = import_pos + 1;
            continue;
        };

        const quote_end = std.mem.indexOfPos(u8, source, quote_start + 1, "\"") orelse {
            pos = quote_start + 1;
            continue;
        };

        const import_path = source[quote_start + 1 .. quote_end];

        if (std.mem.eql(u8, import_path, "std") or std.mem.eql(u8, import_path, "zoop")) {
            pos = quote_end + 1;
            continue;
        }

        const line_start = blk: {
            var i = import_pos;
            while (i > 0) : (i -= 1) {
                if (source[i] == '\n') break :blk i + 1;
            }
            break :blk 0;
        };

        const line_segment = source[line_start..import_pos];

        if (std.mem.indexOf(u8, line_segment, "const")) |const_pos| {
            const after_const = std.mem.trim(u8, line_segment[const_pos + 5 ..], " \t");
            if (std.mem.indexOfScalar(u8, after_const, '=')) |eq_pos| {
                const alias = std.mem.trim(u8, after_const[0..eq_pos], " \t");
                const alias_owned = try allocator.dupe(u8, alias);

                const resolved_path = blk: {
                    if (std.fs.path.dirname(current_file)) |dir| {
                        break :blk try std.fs.path.join(allocator, &.{ dir, import_path });
                    } else {
                        break :blk try allocator.dupe(u8, import_path);
                    }
                };

                try imports.put(alias_owned, resolved_path);
            }
        }

        pos = quote_end + 1;
    }
}

fn scanFileForClasses(
    allocator: std.mem.Allocator,
    source: []const u8,
    file_path: []const u8,
    classes: *std.ArrayListUnmanaged(ClassInfo),
) !void {
    var pos: usize = 0;

    while (pos < source.len) {
        const class_start = std.mem.indexOfPos(u8, source, pos, "zoop.class(") orelse break;

        if (try parseClassDefinition(allocator, source, class_start)) |parsed| {
            defer {
                var mutable = parsed;
                mutable.deinit();
            }

            // Duplicate mixin names array
            var mixin_names_copy = try allocator.alloc([]const u8, parsed.mixin_names.len);
            for (parsed.mixin_names, 0..) |mixin_name, i| {
                mixin_names_copy[i] = try allocator.dupe(u8, mixin_name);
            }

            const class_info = ClassInfo{
                .name = parsed.name,
                .parent_name = parsed.parent_name,
                .mixin_names = mixin_names_copy,
                .fields = try allocator.dupe(FieldDef, parsed.fields),
                .methods = try allocator.dupe(MethodDef, parsed.methods),
                .properties = try allocator.dupe(PropertyDef, parsed.properties),
                .source_start = parsed.source_start,
                .source_end = parsed.source_end,
                .file_path = file_path,
            };

            try classes.append(allocator, class_info);
            pos = parsed.source_end;
        } else {
            pos = class_start + 1;
        }
    }
}

fn filterZoopImport(allocator: std.mem.Allocator, source: []const u8) ![]const u8 {
    var result: std.ArrayList(u8) = .empty;
    defer result.deinit(allocator);

    var pos: usize = 0;
    var line_start: usize = 0;

    while (pos < source.len) {
        const line_end = std.mem.indexOfScalarPos(u8, source, pos, '\n') orelse source.len;
        const line = source[line_start..line_end];

        const is_zoop_import = blk: {
            if (std.mem.indexOf(u8, line, "@import(\"zoop\")")) |_| {
                const trimmed = std.mem.trim(u8, line, " \t\r");
                if (std.mem.startsWith(u8, trimmed, "const ")) {
                    if (std.mem.indexOf(u8, trimmed, "=")) |_| {
                        break :blk true;
                    }
                }
            }
            break :blk false;
        };

        if (!is_zoop_import) {
            try result.appendSlice(allocator, source[line_start..if (line_end < source.len) line_end + 1 else line_end]);
        }

        if (line_end >= source.len) break;
        pos = line_end + 1;
        line_start = pos;
    }

    return try result.toOwnedSlice(allocator);
}

fn processSourceFileWithRegistry(
    allocator: std.mem.Allocator,
    source: []const u8,
    file_path: []const u8,
    registry: *GlobalRegistry,
    config: ClassConfig,
) ![]const u8 {
    const file_info = registry.files.get(file_path) orelse return error.FileNotFound;

    var class_registry = std.StringHashMap(ClassInfo).init(allocator);
    defer class_registry.deinit();

    for (file_info.classes.items) |class_info| {
        try class_registry.put(class_info.name, class_info);
    }

    var it = class_registry.iterator();
    while (it.next()) |entry| {
        var visited = std.StringHashMap(void).init(allocator);
        defer visited.deinit();

        try detectCircularInheritance(
            entry.value_ptr.name,
            entry.value_ptr.parent_name,
            &class_registry,
            &visited,
        );
    }

    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(allocator);

    try output.appendSlice(allocator,
        \\// Auto-generated by zoop-codegen
        \\// DO NOT EDIT - changes will be overwritten
        \\//
        \\// This file was generated from the source file with the same name.
        \\// Class definitions have been enhanced with:
        \\//   - Inherited methods from parent classes
        \\//   - Property getters and setters
        \\//   - Optimized field layouts
        \\
        \\
    );

    var pos: usize = 0;
    var last_class_end: usize = 0;

    while (pos < source.len) {
        const class_start = std.mem.indexOfPos(u8, source, pos, "zoop.class(") orelse break;

        const class_keyword_start = blk: {
            var i = class_start;
            while (i > 0) : (i -= 1) {
                if (source[i] == '\n' or i == 0) {
                    const line_start = if (source[i] == '\n') i + 1 else i;
                    const line = std.mem.trim(u8, source[line_start..class_start], " \t");
                    if (std.mem.startsWith(u8, line, "pub const") or std.mem.startsWith(u8, line, "const")) {
                        break :blk line_start;
                    }
                }
            }
            break :blk class_start;
        };

        const segment = try filterZoopImport(allocator, source[last_class_end..class_keyword_start]);
        defer allocator.free(segment);
        try output.appendSlice(allocator, segment);

        if (try parseClassDefinition(allocator, source, class_start)) |parsed| {
            defer {
                var mutable = parsed;
                mutable.deinit();
            }

            const enhanced = try generateEnhancedClassWithRegistry(allocator, parsed, config, file_path, registry);
            defer allocator.free(enhanced);

            try output.appendSlice(allocator, enhanced);

            last_class_end = parsed.source_end;
            pos = parsed.source_end;
        } else {
            pos = class_start + 1;
        }
    }

    const final_segment = try filterZoopImport(allocator, source[last_class_end..]);
    defer allocator.free(final_segment);
    try output.appendSlice(allocator, final_segment);

    return try output.toOwnedSlice(allocator);
}

fn detectCircularInheritanceGlobal(
    class_name: []const u8,
    parent_ref: ?[]const u8,
    current_file: []const u8,
    registry: *GlobalRegistry,
    visited: *std.StringHashMap(void),
) !void {
    if (parent_ref == null) return;

    try visited.put(class_name, {});

    var current_parent = parent_ref;
    var current_file_path = current_file;

    while (current_parent) |parent| {
        if (visited.contains(parent)) {
            std.debug.print("ERROR: Circular inheritance detected: {s} -> {s}\n", .{ class_name, parent });
            return error.CircularInheritance;
        }

        try visited.put(parent, {});

        const parent_class = try registry.resolveParentReference(parent, current_file_path) orelse break;
        current_parent = parent_class.parent_name;
        current_file_path = parent_class.file_path;
    }
}

fn detectCircularInheritance(
    class_name: []const u8,
    parent_name: ?[]const u8,
    class_registry: *std.StringHashMap(ClassInfo),
    visited: *std.StringHashMap(void),
) !void {
    if (parent_name == null) return;

    try visited.put(class_name, {});

    var current_parent = parent_name;
    while (current_parent) |parent| {
        if (visited.contains(parent)) {
            std.debug.print("ERROR: Circular inheritance detected: {s} -> {s}\n", .{ class_name, parent });
            return error.CircularInheritance;
        }

        try visited.put(parent, {});

        if (class_registry.get(parent)) |parent_info| {
            current_parent = parent_info.parent_name;
        } else {
            break;
        }
    }
}

/// Parse a single class definition starting at the given position
fn parseClassDefinition(
    allocator: std.mem.Allocator,
    source: []const u8,
    start_pos: usize,
) !?struct {
    name: []const u8,
    parent_name: ?[]const u8,
    mixin_names: [][]const u8,
    fields: []FieldDef,
    methods: []MethodDef,
    properties: []PropertyDef,
    source_start: usize,
    source_end: usize,
    allocator: std.mem.Allocator,

    fn deinit(self: *@This()) void {
        for (self.mixin_names) |mixin| {
            self.allocator.free(mixin);
        }
        self.allocator.free(self.mixin_names);
        self.allocator.free(self.fields);
        self.allocator.free(self.methods);
        self.allocator.free(self.properties);
    }
} {
    const struct_start = std.mem.indexOfPos(u8, source, start_pos, "struct") orelse return null;

    const open_brace = std.mem.indexOfPos(u8, source, struct_start, "{") orelse return null;

    const close_brace = findMatchingBrace(source, open_brace) orelse return null;

    const closing_paren = std.mem.indexOfPos(u8, source, close_brace, ");") orelse return null;

    const class_body = source[open_brace + 1 .. close_brace];

    var name_start = std.mem.lastIndexOfScalar(u8, source[0..start_pos], '\n') orelse 0;
    if (name_start > 0) name_start += 1;
    const name_section = source[name_start..start_pos];

    var class_name: []const u8 = "";
    if (std.mem.indexOf(u8, name_section, "const ")) |const_pos| {
        const name_offset = const_pos + 6;
        const eq_pos = std.mem.indexOfPos(u8, name_section, name_offset, "=") orelse return null;
        class_name = std.mem.trim(u8, name_section[name_offset..eq_pos], " \t\r\n");
    }

    if (class_name.len == 0) return null;

    var parent_name: ?[]const u8 = null;
    if (std.mem.indexOf(u8, class_body, "pub const extends")) |pub_extends_pos| {
        const eq_pos = std.mem.indexOfPos(u8, class_body, pub_extends_pos, "=") orelse {
            return null;
        };
        const semicolon_pos = std.mem.indexOfPos(u8, class_body, eq_pos, ";") orelse {
            return null;
        };
        parent_name = std.mem.trim(u8, class_body[eq_pos + 1 .. semicolon_pos], " \t\r\n");
    } else if (std.mem.indexOf(u8, class_body, "extends:")) |extends_pos| {
        const type_start = extends_pos + 8;
        var type_end = type_start;
        while (type_end < class_body.len) : (type_end += 1) {
            const c = class_body[type_end];
            if (c == ',' or c == '\n' or c == '}') break;
        }
        parent_name = std.mem.trim(u8, class_body[type_start..type_end], " \t\r\n");
    }

    // Parse mixins: pub const mixins = .{ Mixin1, Mixin2 };
    var mixin_names: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (mixin_names.items) |mixin| {
            allocator.free(mixin);
        }
        mixin_names.deinit(allocator);
    }

    if (std.mem.indexOf(u8, class_body, "pub const mixins")) |mixins_pos| {
        if (std.mem.indexOfPos(u8, class_body, mixins_pos, "=")) |eq_pos| {
            if (std.mem.indexOfPos(u8, class_body, eq_pos, ".{")) |dot_brace| {
                if (std.mem.indexOfPos(u8, class_body, dot_brace, "}")) |mixins_close| {
                    const mixins_content = std.mem.trim(u8, class_body[dot_brace + 2 .. mixins_close], " \t\r\n");

                    // Parse comma-separated mixin names
                    var it = std.mem.splitSequence(u8, mixins_content, ",");
                    while (it.next()) |mixin_part| {
                        const mixin_name = std.mem.trim(u8, mixin_part, " \t\r\n");
                        if (mixin_name.len > 0) {
                            try mixin_names.append(allocator, try allocator.dupe(u8, mixin_name));
                        }
                    }
                }
            }
        }
    }

    var fields: std.ArrayList(FieldDef) = .empty;
    errdefer fields.deinit(allocator);

    var methods: std.ArrayList(MethodDef) = .empty;
    errdefer methods.deinit(allocator);

    var properties: std.ArrayList(PropertyDef) = .empty;
    errdefer properties.deinit(allocator);

    try parseStructBody(allocator, class_body, &fields, &methods, &properties);

    return .{
        .name = class_name,
        .parent_name = parent_name,
        .mixin_names = try mixin_names.toOwnedSlice(allocator),
        .fields = try fields.toOwnedSlice(allocator),
        .methods = try methods.toOwnedSlice(allocator),
        .properties = try properties.toOwnedSlice(allocator),
        .source_start = name_start,
        .source_end = closing_paren + 2,
        .allocator = allocator,
    };
}

fn findMatchingBrace(source: []const u8, open_pos: usize) ?usize {
    var depth: i32 = 1;
    var pos = open_pos + 1;

    while (pos < source.len) : (pos += 1) {
        switch (source[pos]) {
            '{' => depth += 1,
            '}' => {
                depth -= 1;
                if (depth == 0) return pos;
            },
            else => {},
        }
    }

    return null;
}

fn findMatchingParen(source: []const u8, open_pos: usize) ?usize {
    var depth: i32 = 1;
    var pos = open_pos + 1;

    while (pos < source.len) : (pos += 1) {
        switch (source[pos]) {
            '(' => depth += 1,
            ')' => {
                depth -= 1;
                if (depth == 0) return pos;
            },
            else => {},
        }
    }

    return null;
}

fn replaceFirstSelfType(
    allocator: std.mem.Allocator,
    signature: []const u8,
    new_type: []const u8,
) ![]const u8 {
    if (signature.len < 2) return try allocator.dupe(u8, signature);

    const inner = signature[1 .. signature.len - 1];

    if (std.mem.indexOf(u8, inner, "*const ")) |const_pos| {
        const type_start = const_pos + 7;
        var type_end = type_start;
        while (type_end < inner.len) : (type_end += 1) {
            const c = inner[type_end];
            if (c == ',' or c == ')' or c == ' ') break;
        }

        return try std.fmt.allocPrint(allocator, "({s}*const {s}{s})", .{
            inner[0..const_pos],
            new_type,
            inner[type_end..],
        });
    } else if (std.mem.indexOf(u8, inner, "*")) |ptr_pos| {
        const type_start = ptr_pos + 1;
        var type_end = type_start;
        while (type_end < inner.len) : (type_end += 1) {
            const c = inner[type_end];
            if (c == ',' or c == ')' or c == ' ') break;
        }

        return try std.fmt.allocPrint(allocator, "({s}*{s}{s})", .{
            inner[0..ptr_pos],
            new_type,
            inner[type_end..],
        });
    }

    return try allocator.dupe(u8, signature);
}

fn extractParamNames(allocator: std.mem.Allocator, signature: []const u8) ![]const u8 {
    if (signature.len < 2) return "";

    const inner = signature[1 .. signature.len - 1];

    const first_comma = std.mem.indexOf(u8, inner, ",") orelse return "";

    const params_section = std.mem.trim(u8, inner[first_comma + 1 ..], " \t");

    var result: std.ArrayList(u8) = .empty;
    defer result.deinit(allocator);

    var it = std.mem.splitSequence(u8, params_section, ",");
    var first = true;
    while (it.next()) |param| {
        const trimmed = std.mem.trim(u8, param, " \t");
        if (trimmed.len == 0) continue;

        const colon_pos = std.mem.indexOf(u8, trimmed, ":") orelse continue;
        const param_name = std.mem.trim(u8, trimmed[0..colon_pos], " \t");

        if (!first) {
            try result.appendSlice(allocator, ", ");
        }
        try result.appendSlice(allocator, param_name);
        first = false;
    }

    return result.toOwnedSlice(allocator);
}

fn isStaticMethod(signature: []const u8) bool {
    // A method is static if it doesn't have a 'self' parameter
    // Signature format: (self: *Type, ...) or (self: *const Type, ...)

    if (signature.len < 3) return true; // Empty or invalid signature

    // Skip opening paren
    const inner = std.mem.trim(u8, signature[1 .. signature.len - 1], " \t\r\n");
    if (inner.len == 0) return true; // No parameters

    // Check if first parameter is named 'self'
    // Look for 'self:' or 'self :' at the start
    if (std.mem.startsWith(u8, inner, "self:") or std.mem.startsWith(u8, inner, "self :")) {
        return false; // Has self parameter - not static
    }

    return true; // No self parameter - is static
}

fn parseStructBody(
    allocator: std.mem.Allocator,
    body: []const u8,
    fields: *std.ArrayList(FieldDef),
    methods: *std.ArrayList(MethodDef),
    properties: *std.ArrayList(PropertyDef),
) !void {
    var pos: usize = 0;

    while (pos < body.len) {
        while (pos < body.len and (body[pos] == ' ' or body[pos] == '\t' or body[pos] == '\n' or body[pos] == '\r')) {
            pos += 1;
        }

        if (pos >= body.len) break;

        if (std.mem.startsWith(u8, body[pos..], "pub fn ") or std.mem.startsWith(u8, body[pos..], "fn ")) {
            const fn_start = pos;
            const fn_keyword = if (std.mem.startsWith(u8, body[pos..], "pub fn ")) "pub fn " else "fn ";
            const name_start = pos + fn_keyword.len;

            const paren_pos = std.mem.indexOfPos(u8, body, name_start, "(") orelse {
                pos += 1;
                continue;
            };

            const method_name = std.mem.trim(u8, body[name_start..paren_pos], " \t\r\n");

            const closing_paren = findMatchingParen(body, paren_pos) orelse {
                pos = paren_pos + 1;
                continue;
            };

            const signature = std.mem.trim(u8, body[paren_pos .. closing_paren + 1], " \t\r\n");

            const open_brace_pos = std.mem.indexOfPos(u8, body, closing_paren, "{") orelse {
                pos = closing_paren + 1;
                continue;
            };

            const return_type_section = std.mem.trim(u8, body[closing_paren + 1 .. open_brace_pos], " \t\r\n");

            const close_brace_pos = findMatchingBrace(body, open_brace_pos) orelse {
                pos = open_brace_pos + 1;
                continue;
            };

            const method_source = body[fn_start .. close_brace_pos + 1];

            const is_static = isStaticMethod(signature);

            try methods.append(allocator, .{
                .name = method_name,
                .source = method_source,
                .signature = signature,
                .return_type = return_type_section,
                .is_static = is_static,
            });

            pos = close_brace_pos + 1;
        } else if (std.mem.startsWith(u8, body[pos..], "pub const properties")) {
            // Parse property block: pub const properties = .{ ... };
            const eq_pos = std.mem.indexOfPos(u8, body, pos, "=") orelse {
                pos += 1;
                continue;
            };

            const open_brace = std.mem.indexOfPos(u8, body, eq_pos, "{") orelse {
                pos = eq_pos + 1;
                continue;
            };

            const close_brace = findMatchingBrace(body, open_brace) orelse {
                pos = open_brace + 1;
                continue;
            };

            const props_body = body[open_brace + 1 .. close_brace];
            try parsePropertyBlock(allocator, props_body, properties);

            pos = close_brace + 1;
        } else {
            const line_end = std.mem.indexOfScalarPos(u8, body, pos, '\n') orelse body.len;
            const line = std.mem.trim(u8, body[pos..line_end], " \t\r\n");

            if (line.len > 0 and !std.mem.startsWith(u8, line, "//") and
                !std.mem.startsWith(u8, line, "extends:") and
                !std.mem.startsWith(u8, line, "mixins:"))
            {
                if (std.mem.indexOf(u8, line, ":")) |colon_pos| {
                    const field_name = std.mem.trim(u8, line[0..colon_pos], " \t");

                    const after_colon = line[colon_pos + 1 ..];
                    var type_end = after_colon.len;
                    if (std.mem.indexOfScalar(u8, after_colon, '=')) |eq_pos| {
                        type_end = eq_pos;
                    } else if (std.mem.indexOfScalar(u8, after_colon, ',')) |comma_pos| {
                        type_end = comma_pos;
                    }

                    const field_type = std.mem.trim(u8, after_colon[0..type_end], " \t,");

                    try fields.append(allocator, .{
                        .name = field_name,
                        .type_name = field_type,
                        .default_value = null,
                    });
                }
            }

            pos = line_end + 1;
        }
    }
}

fn parsePropertyBlock(
    allocator: std.mem.Allocator,
    props_body: []const u8,
    properties: *std.ArrayList(PropertyDef),
) !void {
    var pos: usize = 0;

    while (pos < props_body.len) {
        // Skip whitespace
        while (pos < props_body.len and (props_body[pos] == ' ' or props_body[pos] == '\t' or
            props_body[pos] == '\n' or props_body[pos] == '\r'))
        {
            pos += 1;
        }

        if (pos >= props_body.len) break;

        // Look for property: .propName = .{
        if (props_body[pos] != '.') {
            pos += 1;
            continue;
        }

        pos += 1; // Skip '.'

        // Find property name (until '=')
        const eq_pos = std.mem.indexOfPos(u8, props_body, pos, "=") orelse {
            pos += 1;
            continue;
        };

        const prop_name = std.mem.trim(u8, props_body[pos..eq_pos], " \t\r\n");

        // Find opening brace of property definition
        const open_brace = std.mem.indexOfPos(u8, props_body, eq_pos, "{") orelse {
            pos = eq_pos + 1;
            continue;
        };

        const close_brace = findMatchingBrace(props_body, open_brace) orelse {
            pos = open_brace + 1;
            continue;
        };

        const prop_def = props_body[open_brace + 1 .. close_brace];

        // Parse property attributes
        var prop_type: []const u8 = "";
        var prop_access: PropertyAccess = .read_write;

        // Look for .type =
        if (std.mem.indexOf(u8, prop_def, ".type")) |type_pos| {
            const type_eq = std.mem.indexOfPos(u8, prop_def, type_pos, "=") orelse {
                pos = close_brace + 1;
                continue;
            };

            const after_eq = prop_def[type_eq + 1 ..];
            var type_end: usize = 0;
            while (type_end < after_eq.len) : (type_end += 1) {
                const c = after_eq[type_end];
                if (c == ',' or c == '}') break;
            }

            prop_type = std.mem.trim(u8, after_eq[0..type_end], " \t\r\n");
        }

        // Look for .access =
        if (std.mem.indexOf(u8, prop_def, ".access")) |access_pos| {
            if (std.mem.indexOf(u8, prop_def[access_pos..], ".read_only")) |_| {
                prop_access = .read_only;
            }
        }

        if (prop_name.len > 0 and prop_type.len > 0) {
            try properties.append(allocator, .{
                .name = prop_name,
                .type_name = prop_type,
                .access = prop_access,
                .default_value = null,
            });
        }

        pos = close_brace + 1;
    }
}

fn collectAllParentFields(
    allocator: std.mem.Allocator,
    parent_name: ?[]const u8,
    class_registry: *std.StringHashMap(ClassInfo),
    fields_out: *std.ArrayList(FieldDef),
) !void {
    if (parent_name == null) return;

    var hierarchy: std.ArrayList(ClassInfo) = .empty;
    defer hierarchy.deinit(allocator);

    var current_parent = parent_name;
    while (current_parent) |parent| {
        if (class_registry.get(parent)) |parent_info| {
            try hierarchy.append(allocator, parent_info);
            current_parent = parent_info.parent_name;
        } else {
            break;
        }
    }

    var i = hierarchy.items.len;
    while (i > 0) {
        i -= 1;
        const parent_info = hierarchy.items[i];
        for (parent_info.fields) |field| {
            try fields_out.append(allocator, field);
        }
    }
}

fn adaptInitDeinit(
    allocator: std.mem.Allocator,
    source: []const u8,
    child_type: []const u8,
    parent_field_names: std.StringHashMap(void),
) ![]const u8 {
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(allocator);
    const writer = buf.writer(allocator);

    var pos: usize = 0;
    var in_signature = true;
    var found_parent_type: ?[]const u8 = null;

    while (pos < source.len) {
        if (in_signature) {
            if (std.mem.indexOfPos(u8, source, pos, "self: *")) |self_pos| {
                try writer.writeAll(source[pos .. self_pos + 7]);

                const type_start = self_pos + 7;
                var type_end = type_start;
                while (type_end < source.len) : (type_end += 1) {
                    const c = source[type_end];
                    if (!std.ascii.isAlphanumeric(c) and c != '_') break;
                }

                if (found_parent_type == null) {
                    found_parent_type = source[type_start..type_end];
                }

                try writer.writeAll(child_type);
                pos = type_end;
            } else if (std.mem.indexOfPos(u8, source, pos, ") ")) |paren_pos| {
                try writer.writeAll(source[pos .. paren_pos + 2]);

                const type_start = paren_pos + 2;
                var type_end = type_start;
                while (type_end < source.len and source[type_end] != '{') : (type_end += 1) {}

                const return_section = std.mem.trim(u8, source[type_start..type_end], " \t\r\n");

                if (return_section.len > 0) {
                    if (!std.mem.eql(u8, return_section, "void")) {
                        if (found_parent_type == null) {
                            found_parent_type = return_section;
                        }
                        try writer.writeAll(child_type);
                    } else {
                        try writer.writeAll("void");
                    }
                    try writer.writeAll(" ");
                }

                pos = type_end;
                in_signature = false;
            } else {
                try writer.writeByte(source[pos]);
                pos += 1;
            }
        } else {
            if (std.mem.indexOfPos(u8, source, pos, "self.")) |self_dot_pos| {
                try writer.writeAll(source[pos..self_dot_pos]);

                const field_start = self_dot_pos + 5;
                var field_end = field_start;
                while (field_end < source.len) : (field_end += 1) {
                    const c = source[field_end];
                    if (!std.ascii.isAlphanumeric(c) and c != '_') break;
                }

                const field_name = source[field_start..field_end];

                if (parent_field_names.contains(field_name)) {
                    try writer.writeAll("self.super.");
                    try writer.writeAll(field_name);
                } else {
                    try writer.writeAll("self.");
                    try writer.writeAll(field_name);
                }

                pos = field_end;
            } else if (found_parent_type) |parent_type| {
                if (std.mem.indexOfPos(u8, source, pos, parent_type)) |match_pos| {
                    try writer.writeAll(source[pos..match_pos]);
                    try writer.writeAll(child_type);
                    pos = match_pos + parent_type.len;
                } else {
                    try writer.writeAll(source[pos..]);
                    break;
                }
            } else {
                try writer.writeAll(source[pos..]);
                break;
            }
        }
    }

    return try buf.toOwnedSlice(allocator);
}

fn generateEnhancedClassWithRegistry(
    allocator: std.mem.Allocator,
    parsed: anytype,
    config: ClassConfig,
    current_file: []const u8,
    registry: *GlobalRegistry,
) ![]const u8 {
    var code: std.ArrayList(u8) = .empty;
    defer code.deinit(allocator);

    const writer = code.writer(allocator);

    try writer.print("pub const {s} = struct {{\n", .{parsed.name});

    if (parsed.parent_name) |parent_name| {
        try writer.print("    super: {s},\n", .{parent_name});
        if (parsed.properties.len > 0 or parsed.fields.len > 0 or parsed.mixin_names.len > 0) {
            try writer.writeAll("\n");
        }
    }

    // Generate mixin fields
    for (parsed.mixin_names) |mixin_name| {
        // Extract just the type name (handle cases like "base.Mixin")
        const type_name = if (std.mem.lastIndexOfScalar(u8, mixin_name, '.')) |dot_pos|
            mixin_name[dot_pos + 1 ..]
        else
            mixin_name;

        try writer.print("    mixin_{s}: {s},\n", .{ type_name, mixin_name });
    }
    if (parsed.mixin_names.len > 0 and (parsed.properties.len > 0 or parsed.fields.len > 0)) {
        try writer.writeAll("\n");
    }

    for (parsed.properties) |prop| {
        try writer.print("    {s}: {s},\n", .{ prop.name, prop.type_name });
    }

    for (parsed.fields) |field| {
        try writer.print("    {s}: {s},\n", .{ field.name, field.type_name });
    }

    if (parsed.fields.len > 0 and parsed.methods.len > 0) {
        try writer.writeAll("\n");
    }

    for (parsed.methods) |method| {
        try writer.print("    {s}\n", .{method.source});
    }

    if (parsed.parent_name) |parent_ref| {
        if (parsed.methods.len > 0) try writer.writeAll("\n");

        var child_method_names = std.StringHashMap(void).init(allocator);
        defer child_method_names.deinit();
        for (parsed.methods) |method| {
            try child_method_names.put(method.name, {});
        }

        var parent_field_names = std.StringHashMap(void).init(allocator);
        defer parent_field_names.deinit();

        var init_method: ?MethodDef = null;
        var deinit_method: ?MethodDef = null;
        var parent_methods: std.ArrayList(MethodDef) = .empty;
        defer parent_methods.deinit(allocator);

        var current_parent: ?[]const u8 = parent_ref;
        var current_file_path = current_file;

        while (current_parent) |parent| {
            const parent_info = (try registry.resolveParentReference(parent, current_file_path)) orelse break;

            for (parent_info.fields) |field| {
                try parent_field_names.put(field.name, {});
            }

            for (parent_info.properties) |prop| {
                try parent_field_names.put(prop.name, {});
            }

            for (parent_info.methods) |method| {
                const is_init = std.mem.eql(u8, method.name, "init");
                const is_deinit = std.mem.eql(u8, method.name, "deinit");

                if (is_init and !child_method_names.contains("init") and init_method == null) {
                    init_method = method;
                } else if (is_deinit and !child_method_names.contains("deinit") and deinit_method == null) {
                    deinit_method = method;
                } else if (!child_method_names.contains(method.name) and !method.is_static and !is_init and !is_deinit) {
                    try parent_methods.append(allocator, method);
                }
            }

            current_parent = parent_info.parent_name;
            current_file_path = parent_info.file_path;
        }

        if (init_method) |init| {
            const adapted = try adaptInitDeinit(allocator, init.source, parsed.name, parent_field_names);
            defer allocator.free(adapted);
            try writer.print("    {s}\n", .{adapted});
        }

        if (deinit_method) |deinit| {
            const adapted = try adaptInitDeinit(allocator, deinit.source, parsed.name, parent_field_names);
            defer allocator.free(adapted);
            try writer.print("    {s}\n", .{adapted});
        }

        for (parent_methods.items) |method| {
            const child_signature = blk: {
                const sig_inner = std.mem.trim(u8, method.signature[1 .. method.signature.len - 1], " \t");
                if (sig_inner.len == 0) break :blk method.signature;

                const comma_pos = std.mem.indexOfScalar(u8, sig_inner, ',') orelse sig_inner.len;
                const first_param = std.mem.trim(u8, sig_inner[0..comma_pos], " \t");

                if (std.mem.startsWith(u8, first_param, "self:")) {
                    const rest = if (comma_pos < sig_inner.len) sig_inner[comma_pos..] else "";
                    break :blk try std.fmt.allocPrint(allocator, "(self: *{s}{s})", .{ parsed.name, rest });
                } else {
                    break :blk method.signature;
                }
            };
            defer if (!std.mem.eql(u8, child_signature, method.signature)) allocator.free(child_signature);

            const return_type_str = if (method.return_type.len > 0)
                try std.fmt.allocPrint(allocator, " {s}", .{method.return_type})
            else
                "";
            defer if (return_type_str.len > 0) allocator.free(return_type_str);

            try writer.print("    pub inline fn {s}{s}{s}{s} {{\n", .{
                config.method_prefix,
                method.name,
                child_signature,
                return_type_str,
            });

            if (method.return_type.len > 0 and !std.mem.eql(u8, method.return_type, "void")) {
                try writer.print("        return self.super.{s}(", .{method.name});
            } else {
                try writer.print("        self.super.{s}(", .{method.name});
            }

            const sig_inner = std.mem.trim(u8, method.signature[1 .. method.signature.len - 1], " \t");
            if (sig_inner.len > 0) {
                const params_start = std.mem.indexOfScalar(u8, sig_inner, ',') orelse sig_inner.len;
                if (params_start < sig_inner.len) {
                    var param_pos: usize = params_start + 1;
                    var first_param = true;

                    while (param_pos < sig_inner.len) {
                        const param_start = param_pos;
                        const param_end = std.mem.indexOfScalarPos(u8, sig_inner, param_pos, ',') orelse sig_inner.len;
                        const param = std.mem.trim(u8, sig_inner[param_start..param_end], " \t");

                        if (param.len > 0) {
                            if (std.mem.indexOfScalar(u8, param, ':')) |colon_pos| {
                                const param_name = std.mem.trim(u8, param[0..colon_pos], " \t");
                                if (!first_param) try writer.writeAll(", ");
                                try writer.print("{s}", .{param_name});
                                first_param = false;
                            }
                        }

                        param_pos = param_end + 1;
                    }
                }
            }

            try writer.writeAll(");\n");
            try writer.writeAll("    }\n");
        }
    }

    if (parsed.properties.len > 0) {
        if (parsed.methods.len > 0 or parsed.parent_name != null) try writer.writeAll("\n");

        for (parsed.properties) |prop| {
            try writer.print("    pub inline fn {s}{s}(self: *const @This()) {s} {{\n", .{
                config.getter_prefix,
                prop.name,
                prop.type_name,
            });
            try writer.print("        return self.{s};\n", .{prop.name});
            try writer.writeAll("    }\n");

            if (prop.access == .read_write) {
                try writer.print("    pub inline fn {s}{s}(self: *@This(), value: {s}) void {{\n", .{
                    config.setter_prefix,
                    prop.name,
                    prop.type_name,
                });
                try writer.print("        self.{s} = value;\n", .{prop.name});
                try writer.writeAll("    }\n");
            }
        }
    }

    try writer.writeAll("};\n");

    return try code.toOwnedSlice(allocator);
}

/// Generate complete class code with all fields and methods
pub fn generateClassCode(allocator: std.mem.Allocator, spec: ClassSpec) ![]const u8 {
    var code = std.ArrayList(u8).init(allocator);
    defer code.deinit();

    const writer = code.writer();

    // Start struct
    try writer.print("pub const {s} = struct {{\n", .{spec.name});

    // Generate fields
    try generateFields(writer, spec);

    // Generate parent methods (if parent exists)
    if (spec.parent) |Parent| {
        try generateParentMethods(writer, Parent, spec.definition, spec.config);
    }

    // Generate property methods
    try generatePropertyMethods(writer, spec);

    // Copy child's own methods
    try generateChildMethods(writer, spec.definition);

    // End struct
    try writer.writeAll("};\n");

    return code.toOwnedSlice();
}

/// Generate all fields (parent + mixin + property backing + own)
fn generateFields(writer: anytype, spec: ClassSpec) !void {
    // Parent fields first (never reordered)
    if (spec.parent) |Parent| {
        const parent_info = @typeInfo(Parent);
        if (parent_info == .@"struct") {
            const parent_struct = parent_info.@"struct";
            for (parent_struct.fields) |field| {
                try writer.print("    {s}: {s},\n", .{ field.name, @typeName(field.type) });
            }
        }
    }

    // TODO: Mixin fields (sorted by alignment)

    // TODO: Property backing fields (sorted by alignment)

    // Own fields (sorted by alignment)
    const def_info = @typeInfo(spec.definition);
    if (def_info == .@"struct") {
        const def_struct = def_info.@"struct";

        // Filter out special decls
        var own_fields = std.ArrayList(std.builtin.Type.StructField).init(std.heap.page_allocator);
        defer own_fields.deinit();

        for (def_struct.fields) |field| {
            // Skip special fields like 'extends'
            if (!isSpecialField(field.name)) {
                try own_fields.append(field);
            }
        }

        // Sort by alignment
        const sorted = try sortFieldsByAlignment(own_fields.items);
        defer std.heap.page_allocator.free(sorted);

        for (sorted) |field| {
            try writer.print("    {s}: {s},\n", .{ field.name, @typeName(field.type) });
        }
    }

    try writer.writeAll("\n");
}

/// Generate wrapper methods for parent methods (with prefix, skip overrides)
fn generateParentMethods(
    writer: anytype,
    comptime ParentType: type,
    comptime ChildDef: type,
    config: ClassConfig,
) !void {
    const parent_info = @typeInfo(ParentType);
    if (parent_info == .@"struct") {
        const parent_struct = parent_info.@"struct";

        inline for (parent_struct.decls) |decl| {
            if (!decl.is_pub) continue;

            // Check if this is a function
            const decl_value = @field(ParentType, decl.name);
            const decl_type_info = @typeInfo(@TypeOf(decl_value));

            if (decl_type_info != .@"fn") continue;

            // Check if child overrides this method
            if (@hasDecl(ChildDef, decl.name)) continue;

            // Generate wrapper with prefix
            try writer.print("    pub inline fn {s}{s}(self: *@This()) ", .{
                config.method_prefix,
                decl.name,
            });

            // TODO: Get proper return type
            try writer.writeAll("void {\n");

            // TODO: Call parent implementation
            try writer.print("        _ = self;\n", .{});

            try writer.writeAll("    }\n\n");
        }
    }
}

/// Generate property getters/setters with configured prefixes
fn generatePropertyMethods(writer: anytype, spec: ClassSpec) !void {
    if (!@hasDecl(spec.definition, "properties")) return;

    const properties = spec.definition.properties;
    const props_info = @typeInfo(@TypeOf(properties));

    if (props_info == .@"struct") {
        const props_struct = props_info.@"struct";

        inline for (props_struct.fields) |prop_field| {
            const prop_def = @field(properties, prop_field.name);

            // Check if child overrides getter
            const getter_name = std.fmt.comptimePrint("{s}{s}", .{ spec.config.getter_prefix, prop_field.name });
            if (!@hasDecl(spec.definition, getter_name)) {
                // Generate getter
                try writer.print("    pub inline fn {s}(self: *@This()) {s} {{\n", .{
                    getter_name,
                    @typeName(prop_def.type),
                });
                try writer.print("        return self._{s};\n", .{prop_field.name});
                try writer.writeAll("    }\n\n");
            }

            // Generate setter if read_write
            if (prop_def.access == .read_write) {
                const setter_name = std.fmt.comptimePrint("{s}{s}", .{ spec.config.setter_prefix, prop_field.name });
                if (!@hasDecl(spec.definition, setter_name)) {
                    try writer.print("    pub inline fn {s}(self: *@This(), value: {s}) void {{\n", .{
                        setter_name,
                        @typeName(prop_def.type),
                    });
                    try writer.print("        self._{s} = value;\n", .{prop_field.name});
                    try writer.writeAll("    }\n\n");
                }
            }
        }
    }
}

/// Copy child's own method definitions
fn generateChildMethods(writer: anytype, comptime ChildDef: type) !void {
    _ = writer;
    const def_info = @typeInfo(ChildDef);
    if (def_info == .@"struct") {
        const def_struct = def_info.@"struct";

        inline for (def_struct.decls) |decl| {
            if (!decl.is_pub) continue;
            if (isSpecialDecl(decl.name)) continue;

            // TODO: Copy method source code
            // This is the hard part - we can't easily get method source
        }
    }
}

fn isSpecialField(name: []const u8) bool {
    return std.mem.eql(u8, name, "extends") or
        std.mem.eql(u8, name, "mixins") or
        std.mem.eql(u8, name, "properties");
}

fn isSpecialDecl(name: []const u8) bool {
    return std.mem.eql(u8, name, "extends") or
        std.mem.eql(u8, name, "mixins") or
        std.mem.eql(u8, name, "properties");
}

fn sortFieldsByAlignment(fields: []const std.builtin.Type.StructField) ![]std.builtin.Type.StructField {
    const sorted = try std.heap.page_allocator.dupe(std.builtin.Type.StructField, fields);

    // Sort by alignment descending, then by size descending
    std.mem.sort(std.builtin.Type.StructField, sorted, {}, struct {
        fn lessThan(_: void, a: std.builtin.Type.StructField, b: std.builtin.Type.StructField) bool {
            const a_align = a.alignment;
            const b_align = b.alignment;

            if (a_align != b_align) {
                return a_align > b_align;
            }

            // Same alignment, sort by size (can't get size from StructField directly)
            return false;
        }
    }.lessThan);

    return sorted;
}
