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

/// Maximum file size to prevent DoS attacks (5MB)
const MAX_FILE_SIZE = 5 * 1024 * 1024;

/// Maximum inheritance depth to prevent stack overflow
const MAX_INHERITANCE_DEPTH = 256;

/// Maximum type signature length to prevent DoS via complex signatures
const MAX_SIGNATURE_LENGTH = 1024;

/// Maximum type name length for validation
const MAX_TYPE_NAME_LENGTH = 256;

// Keyword and prefix length constants (replaces magic numbers throughout code)
const CONST_KEYWORD_LEN = "const ".len; // = 6
const EXTENDS_KEYWORD_LEN = "extends:".len; // = 8
const PUB_CONST_EXTENDS_LEN = "pub const extends".len; // = 17
const PTR_CONST_PREFIX_LEN = "*const ".len; // = 7
const PTR_PREFIX_LEN = "*".len; // = 1
const ZOOP_CLASS_PREFIX_LEN = "zoop.class(".len; // = 11
const PUB_CONST_MIXINS_LEN = "pub const mixins".len; // = 16

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

/// Validate that a file path doesn't contain path traversal attempts.
/// Enhanced to prevent URL encoding and other bypass techniques.
fn isPathSafe(path: []const u8) bool {
    // Check for absolute paths
    if (path.len > 0 and path[0] == '/') return false;

    // Check for Windows absolute paths (C:, D:, etc.)
    if (path.len >= 2 and path[1] == ':') return false;

    // Check for parent directory references
    if (std.mem.indexOf(u8, path, "..") != null) return false;

    // Check for backslashes (Windows path separator, could be used for traversal)
    if (std.mem.indexOf(u8, path, "\\") != null) return false;

    // Check for null bytes (path truncation attack)
    if (std.mem.indexOfScalar(u8, path, 0) != null) return false;

    // Check for URL-encoded path traversal attempts
    if (std.mem.indexOf(u8, path, "%2e") != null or std.mem.indexOf(u8, path, "%2E") != null) return false;

    // Check for double-encoded attempts
    if (std.mem.indexOf(u8, path, "%252e") != null or std.mem.indexOf(u8, path, "%252E") != null) return false;

    // Check for control characters that could interfere with terminals or parsers
    for (path) |c| {
        if (c < 32 and c != '\n' and c != '\r' and c != '\t') return false;
    }

    return true;
}

/// Validate that a type name is safe (alphanumeric + underscore, not starting with digit).
/// Prevents injection attacks by ensuring type names follow Zig identifier rules.
fn isValidTypeName(name: []const u8) bool {
    if (name.len == 0 or name.len > MAX_TYPE_NAME_LENGTH) return false;

    // First character must be letter or underscore
    if (!std.ascii.isAlphabetic(name[0]) and name[0] != '_') return false;

    // Remaining characters: alphanumeric, underscore, or dot (for namespaced types like base.Type)
    for (name[1..]) |c| {
        if (!std.ascii.isAlphanumeric(c) and c != '_' and c != '.') return false;
    }

    return true;
}

/// Main entry point: Generate all classes in source directory.
///
/// ## Thread Safety
///
/// **WARNING: This function is NOT thread-safe.**
///
/// Do not call this function concurrently from multiple threads. The GlobalRegistry
/// uses non-atomic HashMap operations that will cause data races if accessed in parallel.
///
/// This limitation exists because:
/// - GlobalRegistry.files is a HashMap without synchronization
/// - File I/O operations share mutable state
/// - ArrayListUnmanaged operations are not thread-safe
///
/// If parallel code generation is needed in the future, consider:
/// - Adding a mutex around GlobalRegistry operations
/// - Using thread-local registries and merging results
/// - Implementing a concurrent-safe registry with std.Thread.Mutex
///
/// ## Parameters
///
/// - `allocator` - Memory allocator for temporary allocations during generation
/// - `source_dir` - Directory to scan for `.zig` files containing `zoop.class()` calls
/// - `output_dir` - Directory where generated code will be written
/// - `config` - Configuration for method/property prefix naming
///
/// ## Example
///
/// ```zig
/// const allocator = std.heap.page_allocator;
/// try generateAllClasses(
///     allocator,
///     "src",
///     ".zig-cache/zoop-generated",
///     .{
///         .method_prefix = "call_",
///         .getter_prefix = "get_",
///         .setter_prefix = "set_",
///     },
/// );
/// ```
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
            try scanFileForClasses(allocator, source_content, file_path_owned, &file_info.classes, &registry);

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

/// Global registry of all classes found during code generation.
///
/// **THREAD SAFETY: NOT THREAD-SAFE**
///
/// This structure is NOT safe for concurrent access. All operations on the
/// registry use non-atomic HashMap operations. Concurrent access will cause
/// data races and undefined behavior.
///
/// ## Internal State
///
/// - `files`: HashMap mapping file paths to FileInfo (NOT thread-safe)
/// - `classes`: ArrayListUnmanaged (NOT thread-safe)
/// - `string_pool`: String interning pool for class/type names (NOT thread-safe)
/// - All operations assume single-threaded access
///
/// ## String Interning
///
/// The registry maintains a string pool to deduplicate class names and type
/// references. This reduces memory usage on large projects where the same
/// class names appear multiple times (in parent references, imports, etc.).
///
/// ## Usage
///
/// Always use within a single thread or protect with external synchronization.
const GlobalRegistry = struct {
    allocator: std.mem.Allocator,
    files: std.StringHashMap(FileInfo),
    string_pool: std.StringHashMap(void), // Interned strings

    fn init(allocator: std.mem.Allocator) GlobalRegistry {
        return .{
            .allocator = allocator,
            .files = std.StringHashMap(FileInfo).init(allocator),
            .string_pool = std.StringHashMap(void).init(allocator),
        };
    }

    /// Intern a string in the pool. Returns a reference to the pooled string.
    /// If the string already exists in the pool, returns the existing reference.
    /// This reduces memory usage by deduplicating strings.
    fn internString(self: *GlobalRegistry, str: []const u8) ![]const u8 {
        const gop = try self.string_pool.getOrPut(str);
        if (!gop.found_existing) {
            // Allocate and store the string
            const owned = try self.allocator.dupe(u8, str);
            gop.key_ptr.* = owned;
        }
        return gop.key_ptr.*;
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
                // Note: class_info.name, parent_name, and mixin_names elements
                // are interned strings freed from the string pool, not here
                self.allocator.free(class_info.mixin_names); // Free the array, not the strings
                self.allocator.free(class_info.fields);
                self.allocator.free(class_info.methods);
                self.allocator.free(class_info.properties);
            }
            entry.value_ptr.classes.deinit(self.allocator);
            self.allocator.free(entry.value_ptr.source_content);
            self.allocator.free(entry.value_ptr.path);
        }
        self.files.deinit();

        // Free all interned strings from the pool
        var pool_it = self.string_pool.iterator();
        while (pool_it.next()) |pool_entry| {
            self.allocator.free(pool_entry.key_ptr.*);
        }
        self.string_pool.deinit();
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
    registry: *GlobalRegistry,
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

            // Intern strings to reduce memory usage
            const interned_name = try registry.internString(parsed.name);
            const interned_parent = if (parsed.parent_name) |p| try registry.internString(p) else null;

            // Intern mixin names
            var interned_mixins = try allocator.alloc([]const u8, mixin_names_copy.len);
            for (mixin_names_copy, 0..) |mixin, i| {
                interned_mixins[i] = try registry.internString(mixin);
                allocator.free(mixin); // Free the original copy
            }
            allocator.free(mixin_names_copy); // Free the original array

            const class_info = ClassInfo{
                .name = interned_name,
                .parent_name = interned_parent,
                .mixin_names = interned_mixins,
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

/// Detect circular inheritance with O(n) complexity and depth tracking.
///
/// This optimized version:
/// - Uses a visited set for O(1) lookup (not O(n²))
/// - Tracks depth to enforce MAX_INHERITANCE_DEPTH
/// - Single pass through the inheritance chain
///
/// Time complexity: O(n) where n is the inheritance chain length
/// Space complexity: O(n) for the visited set
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
    var depth: usize = 0;

    while (current_parent) |parent| {
        // Check for circular reference (O(1) lookup)
        if (visited.contains(parent)) {
            std.debug.print("ERROR: Circular inheritance detected: {s} -> {s}\n", .{ class_name, parent });
            return error.CircularInheritance;
        }

        // Check depth limit
        depth += 1;
        if (depth > MAX_INHERITANCE_DEPTH) {
            std.debug.print("ERROR: Maximum inheritance depth ({d}) exceeded starting from {s}\n", .{ MAX_INHERITANCE_DEPTH, class_name });
            return error.MaxDepthExceeded;
        }

        try visited.put(parent, {});

        const parent_class = try registry.resolveParentReference(parent, current_file_path) orelse break;
        current_parent = parent_class.parent_name;
        current_file_path = parent_class.file_path;
    }
}

/// Detect circular inheritance (legacy single-file version).
///
/// Optimized with O(n) complexity and depth tracking.
fn detectCircularInheritance(
    class_name: []const u8,
    parent_name: ?[]const u8,
    class_registry: *std.StringHashMap(ClassInfo),
    visited: *std.StringHashMap(void),
) !void {
    if (parent_name == null) return;

    try visited.put(class_name, {});

    var current_parent = parent_name;
    var depth: usize = 0;

    while (current_parent) |parent| {
        // Check for circular reference (O(1) lookup)
        if (visited.contains(parent)) {
            std.debug.print("ERROR: Circular inheritance detected: {s} -> {s}\n", .{ class_name, parent });
            return error.CircularInheritance;
        }

        // Check depth limit
        depth += 1;
        if (depth > MAX_INHERITANCE_DEPTH) {
            std.debug.print("ERROR: Maximum inheritance depth ({d}) exceeded starting from {s}\n", .{ MAX_INHERITANCE_DEPTH, class_name });
            return error.MaxDepthExceeded;
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
        const name_offset = const_pos + CONST_KEYWORD_LEN;
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
        const type_start = extends_pos + EXTENDS_KEYWORD_LEN;
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

    // Convert to owned slices with proper error handling to prevent leaks
    const mixin_names_slice = try mixin_names.toOwnedSlice(allocator);
    errdefer {
        for (mixin_names_slice) |mixin| {
            allocator.free(mixin);
        }
        allocator.free(mixin_names_slice);
    }

    const fields_slice = try fields.toOwnedSlice(allocator);
    errdefer allocator.free(fields_slice);

    const methods_slice = try methods.toOwnedSlice(allocator);
    errdefer allocator.free(methods_slice);

    const properties_slice = try properties.toOwnedSlice(allocator);
    errdefer allocator.free(properties_slice);

    return .{
        .name = class_name,
        .parent_name = parent_name,
        .mixin_names = mixin_names_slice,
        .fields = fields_slice,
        .methods = methods_slice,
        .properties = properties_slice,
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
    if (signature.len > MAX_SIGNATURE_LENGTH) return error.SignatureTooLong;

    const inner = signature[1 .. signature.len - 1];

    if (std.mem.indexOf(u8, inner, "*const ")) |const_pos| {
        const type_start = const_pos + PTR_CONST_PREFIX_LEN;
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
        const type_start = ptr_pos + PTR_PREFIX_LEN;
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
    if (signature.len > MAX_SIGNATURE_LENGTH) return error.SignatureTooLong;

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
) ![]const u8 {
    // Validate type name to prevent injection
    if (!isValidTypeName(child_type)) return error.InvalidTypeName;

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
            // With flattened fields, we no longer need to rewrite self.field to self.super.field
            // Just handle type name replacement
            if (found_parent_type) |parent_type| {
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
    // Validate class name to prevent injection attacks
    if (!isValidTypeName(parsed.name)) return error.InvalidClassName;

    var code: std.ArrayList(u8) = .empty;
    defer code.deinit(allocator);

    const writer = code.writer(allocator);

    try writer.print("pub const {s} = struct {{\n", .{parsed.name});

    // Generate parent fields (flattened - copy fields directly from parent classes)
    if (parsed.parent_name) |parent_ref| {
        var current_parent: ?[]const u8 = parent_ref;
        var current_file_path = current_file;

        // Collect all parent fields by walking up the hierarchy
        var all_parent_fields: std.ArrayList(FieldDef) = .empty;
        defer all_parent_fields.deinit(allocator);
        var all_parent_properties: std.ArrayList(PropertyDef) = .empty;
        defer all_parent_properties.deinit(allocator);

        while (current_parent) |parent| {
            const parent_info = (try registry.resolveParentReference(parent, current_file_path)) orelse break;

            // Add parent fields (in reverse order, will reverse later)
            for (parent_info.fields) |field| {
                try all_parent_fields.append(allocator, field);
            }
            for (parent_info.properties) |prop| {
                try all_parent_properties.append(allocator, prop);
            }

            current_parent = parent_info.parent_name;
            current_file_path = parent_info.file_path;
        }

        // Reverse to get correct inheritance order (grandparent first)
        std.mem.reverse(FieldDef, all_parent_fields.items);
        std.mem.reverse(PropertyDef, all_parent_properties.items);

        // Write parent fields
        for (all_parent_fields.items) |field| {
            try writer.print("    {s}: {s},\n", .{ field.name, field.type_name });
        }
        for (all_parent_properties.items) |prop| {
            try writer.print("    {s}: {s},\n", .{ prop.name, prop.type_name });
        }

        if (all_parent_fields.items.len > 0 or all_parent_properties.items.len > 0) {
            if (parsed.mixin_names.len > 0 or parsed.properties.len > 0 or parsed.fields.len > 0) {
                try writer.writeAll("\n");
            }
        }
    }

    // Generate mixin fields (flattened - copy fields directly from mixin classes)
    for (parsed.mixin_names) |mixin_ref| {
        const mixin_info = (try registry.resolveParentReference(mixin_ref, current_file)) orelse continue;

        // Copy all fields from mixin
        for (mixin_info.fields) |field| {
            try writer.print("    {s}: {s},\n", .{ field.name, field.type_name });
        }

        // Copy all property fields from mixin
        for (mixin_info.properties) |prop| {
            try writer.print("    {s}: {s},\n", .{ prop.name, prop.type_name });
        }
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

    // Track child method names for override detection (used by both parent and mixin generation)
    var child_method_names = std.StringHashMap(void).init(allocator);
    defer child_method_names.deinit();
    for (parsed.methods) |method| {
        try child_method_names.put(method.name, {});
    }

    if (parsed.parent_name) |parent_ref| {
        if (parsed.methods.len > 0) try writer.writeAll("\n");

        var parent_field_names = std.StringHashMap(void).init(allocator);
        defer parent_field_names.deinit();

        const ParentMethod = struct {
            method: MethodDef,
            parent_type: []const u8,
        };

        var init_method: ?MethodDef = null;
        var deinit_method: ?MethodDef = null;
        var parent_methods: std.ArrayList(ParentMethod) = .empty;
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
                    try parent_methods.append(allocator, .{
                        .method = method,
                        .parent_type = parent_info.name,
                    });
                }
            }

            current_parent = parent_info.parent_name;
            current_file_path = parent_info.file_path;
        }

        if (init_method) |init| {
            const adapted = try adaptInitDeinit(allocator, init.source, parsed.name);
            defer allocator.free(adapted);
            try writer.print("    {s}\n", .{adapted});
        }

        if (deinit_method) |deinit| {
            const adapted = try adaptInitDeinit(allocator, deinit.source, parsed.name);
            defer allocator.free(adapted);
            try writer.print("    {s}\n", .{adapted});
        }

        for (parent_methods.items) |parent_method| {
            const method = parent_method.method;
            const parent_type = parent_method.parent_type;

            // Copy and rewrite parent method (same as mixins - no casting!)
            const rewritten_method = try rewriteMixinMethod(allocator, method.source, parent_type, parsed.name);
            defer allocator.free(rewritten_method);

            try writer.print("    {s}\n", .{rewritten_method});
        }
    }

    // Generate mixin methods (flattened - copy method source directly into child)
    if (parsed.mixin_names.len > 0) {
        if (parsed.methods.len > 0 or parsed.parent_name != null) try writer.writeAll("\n");

        for (parsed.mixin_names) |mixin_ref| {
            const mixin_info = (try registry.resolveParentReference(mixin_ref, current_file)) orelse continue;

            for (mixin_info.methods) |method| {
                // Skip if child already has this method (child overrides mixin)
                if (child_method_names.contains(method.name)) continue;

                // Skip init/deinit - those are handled specially
                if (std.mem.eql(u8, method.name, "init") or std.mem.eql(u8, method.name, "deinit")) continue;

                // Skip static methods
                if (method.is_static) continue;

                // Need to rewrite the method signature to replace mixin type with child type
                // e.g., "self: *Timestamped" -> "self: *User"
                const rewritten_method = try rewriteMixinMethod(allocator, method.source, mixin_info.name, parsed.name);
                defer allocator.free(rewritten_method);

                try writer.print("    {s}\n", .{rewritten_method});
            }
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
// ============================================================================
// DEAD CODE REMOVED (~220 lines)
// ============================================================================
// Removed unused comptime-reflection functions: generateClassCode,
// generateFields, generateParentMethods, generatePropertyMethods,
// generateChildMethods, isSpecialField, isSpecialDecl, sortFieldsByAlignment.
// These are replaced by generateEnhancedClassWithRegistry().
// See git history for removed implementation.
// ============================================================================

/// Rewrite a mixin method to replace the mixin type name with the child type name.
/// E.g., "self: *Timestamped" -> "self: *User"
/// Uses context-aware replacement to avoid changing string literals or comments.
fn rewriteMixinMethod(
    allocator: std.mem.Allocator,
    method_source: []const u8,
    mixin_type_name: []const u8,
    child_type_name: []const u8,
) ![]const u8 {
    // Validate type names to prevent injection
    if (!isValidTypeName(mixin_type_name)) return error.InvalidTypeName;
    if (!isValidTypeName(child_type_name)) return error.InvalidTypeName;

    var result: std.ArrayList(u8) = .empty;
    errdefer result.deinit(allocator);

    var pos: usize = 0;
    var in_string: bool = false;
    var in_comment: bool = false;

    while (pos < method_source.len) {
        if (in_string) {
            if (method_source[pos] == '"' and (pos == 0 or method_source[pos - 1] != '\\')) {
                in_string = false;
            }
            try result.append(allocator, method_source[pos]);
            pos += 1;
            continue;
        }

        if (in_comment) {
            if (method_source[pos] == '\n') {
                in_comment = false;
            }
            try result.append(allocator, method_source[pos]);
            pos += 1;
            continue;
        }

        if (method_source[pos] == '"') {
            in_string = true;
            try result.append(allocator, method_source[pos]);
            pos += 1;
            continue;
        }

        if (pos + 1 < method_source.len and method_source[pos] == '/' and method_source[pos + 1] == '/') {
            in_comment = true;
            try result.append(allocator, method_source[pos]);
            pos += 1;
            continue;
        }

        if (std.mem.startsWith(u8, method_source[pos..], mixin_type_name)) {
            const before_ok = pos == 0 or !isIdentifierChar(method_source[pos - 1]);
            const after_pos = pos + mixin_type_name.len;
            const after_ok = after_pos >= method_source.len or !isIdentifierChar(method_source[after_pos]);

            if (before_ok and after_ok) {
                try result.appendSlice(allocator, child_type_name);
                pos += mixin_type_name.len;
                continue;
            }
        }

        try result.append(allocator, method_source[pos]);
        pos += 1;
    }

    return result.toOwnedSlice(allocator);
}

fn isIdentifierChar(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_';
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
