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

    // Load cache manifest
    const cache_path = ".zig-cache/zoop-manifest.json";
    var cache_manifest = try CacheManifest.load(allocator, cache_path);
    defer cache_manifest.deinit(allocator);

    // Track which files need regeneration
    var files_to_regenerate = std.StringHashMap(void).init(allocator);
    defer {
        var it = files_to_regenerate.keyIterator();
        while (it.next()) |key| {
            allocator.free(key.*);
        }
        files_to_regenerate.deinit();
    }

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
            std.mem.indexOf(u8, source_content, "zoop.mixin(") != null or
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

            // Check if this file needs regeneration
            const cache_entry = cache_manifest.entries.get(entry.path);
            if (try needsRegeneration(allocator, source_path, source_content, cache_entry)) {
                try files_to_regenerate.put(try allocator.dupe(u8, entry.path), {});
            }
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

    // Build descendant map to track dependencies
    var descendant_map = try registry.buildDescendantMap();
    defer {
        var desc_it = descendant_map.iterator();
        while (desc_it.next()) |desc_entry| {
            desc_entry.value_ptr.deinit(allocator);
        }
        descendant_map.deinit();
    }

    // Add descendants of changed files to regeneration list
    var files_to_check = std.ArrayList([]const u8){};
    defer files_to_check.deinit(allocator);

    var regen_it = files_to_regenerate.keyIterator();
    while (regen_it.next()) |file_path| {
        try files_to_check.append(allocator, file_path.*);
    }

    for (files_to_check.items) |file_path| {
        // Get classes in this file
        const file_info = registry.files.get(file_path) orelse continue;
        for (file_info.classes.items) |class_info| {
            // Find descendants of each class
            const descendants = descendant_map.get(class_info.name) orelse continue;
            for (descendants.items) |descendant_name| {
                // Find which file contains this descendant
                var find_it = registry.files.iterator();
                while (find_it.next()) |find_entry| {
                    for (find_entry.value_ptr.classes.items) |find_class| {
                        if (std.mem.eql(u8, find_class.name, descendant_name)) {
                            // Only dupe the key if not already in the map
                            if (!files_to_regenerate.contains(find_entry.key_ptr.*)) {
                                try files_to_regenerate.put(try allocator.dupe(u8, find_entry.key_ptr.*), {});
                            }
                            break;
                        }
                    }
                }
            }
        }
    }

    // PASS 2: Generate code for each file
    var classes_generated: usize = 0;
    var file_it = registry.files.iterator();

    // New cache manifest to save
    var new_cache_manifest = CacheManifest.init(allocator);
    defer new_cache_manifest.deinit(allocator);

    while (file_it.next()) |entry| {
        const file_path = entry.key_ptr.*;
        const file_info = entry.value_ptr.*;

        // Validate path again before writing (defense in depth)
        if (!isPathSafe(file_path)) {
            std.debug.print("Error: Refusing to write file with unsafe path: {s}\n", .{file_path});
            return error.UnsafePath;
        }

        // Only generate if file needs regeneration
        if (files_to_regenerate.contains(file_path)) {
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

        // Update cache entry for this file
        const source_path = try std.fs.path.join(allocator, &.{ source_dir, file_path });
        defer allocator.free(source_path);

        const content_hash = computeContentHash(file_info.source_content);
        const mtime_ns = try getFileMtime(source_path);

        // Collect class names and parent names
        const class_names = try allocator.alloc([]const u8, file_info.classes.items.len);
        for (file_info.classes.items, 0..) |class_info, i| {
            class_names[i] = try allocator.dupe(u8, class_info.name);
        }

        var parent_names_list = std.ArrayList([]const u8){};
        defer parent_names_list.deinit(allocator);
        for (file_info.classes.items) |class_info| {
            if (class_info.parent_name) |parent| {
                try parent_names_list.append(allocator, try allocator.dupe(u8, parent));
            }
        }
        const parent_names = try parent_names_list.toOwnedSlice(allocator);

        const cache_entry = CacheEntry{
            .source_path = try allocator.dupe(u8, file_path),
            .content_hash = content_hash,
            .mtime_ns = mtime_ns,
            .class_names = class_names,
            .parent_names = parent_names,
        };

        const cache_key = try allocator.dupe(u8, file_path);
        try new_cache_manifest.entries.put(cache_key, cache_entry);
    }

    // Save updated cache manifest
    try new_cache_manifest.save(allocator, cache_path);

    std.debug.print("\nProcessed {} files, generated {} class files\n", .{ files_processed, classes_generated });
}

/// Parsed method definition
const MethodDef = struct {
    name: []const u8,
    source: []const u8,
    signature: []const u8,
    return_type: []const u8,
    is_static: bool = false,
    doc_comment: ?[]const u8 = null,
};

/// Parsed field definition
const FieldDef = struct {
    name: []const u8,
    type_name: []const u8,
    default_value: ?[]const u8,
    estimated_size: usize = 0,
    doc_comment: ?[]const u8 = null,
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
    doc_comment: ?[]const u8 = null,
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
    file_doc: ?[]const u8 = null,
    class_doc: ?[]const u8 = null,

    fn deinit(self: *ParsedClass) void {
        for (self.mixin_names) |mixin_name| {
            self.allocator.free(mixin_name);
        }
        self.allocator.free(self.mixin_names);

        // Free doc comments in fields
        for (self.fields) |field| {
            if (field.doc_comment) |doc| {
                self.allocator.free(doc);
            }
        }
        self.allocator.free(self.fields);

        // Free doc comments in methods
        for (self.methods) |method| {
            if (method.doc_comment) |doc| {
                self.allocator.free(doc);
            }
        }
        self.allocator.free(self.methods);

        // Free doc comments in properties
        for (self.properties) |prop| {
            if (prop.doc_comment) |doc| {
                self.allocator.free(doc);
            }
        }
        self.allocator.free(self.properties);

        if (self.file_doc) |doc| {
            self.allocator.free(doc);
        }
        if (self.class_doc) |doc| {
            self.allocator.free(doc);
        }
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

/// Cache entry for a single zoop source file
const CacheEntry = struct {
    /// Path to the source file (relative to source directory)
    source_path: []const u8,
    /// SHA-256 hash of source file content
    content_hash: [32]u8,
    /// Modification timestamp (nanoseconds since epoch)
    mtime_ns: i128,
    /// List of class names defined in this file
    class_names: [][]const u8,
    /// List of parent class names (for dependency tracking)
    parent_names: [][]const u8,
};

/// Cache manifest containing all file cache entries
const CacheManifest = struct {
    /// Version of the cache format (for future compatibility)
    version: u32 = 1,
    /// Map of source file path -> cache entry
    entries: std.StringHashMap(CacheEntry),

    fn init(allocator: std.mem.Allocator) CacheManifest {
        return .{
            .entries = std.StringHashMap(CacheEntry).init(allocator),
        };
    }

    fn deinit(self: *CacheManifest, allocator: std.mem.Allocator) void {
        var it = self.entries.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.source_path);
            for (entry.value_ptr.class_names) |name| {
                allocator.free(name);
            }
            allocator.free(entry.value_ptr.class_names);
            for (entry.value_ptr.parent_names) |name| {
                allocator.free(name);
            }
            allocator.free(entry.value_ptr.parent_names);
        }
        self.entries.deinit();
    }

    /// Load cache manifest from file
    fn load(allocator: std.mem.Allocator, cache_path: []const u8) !CacheManifest {
        const file = std.fs.cwd().openFile(cache_path, .{}) catch |err| {
            if (err == error.FileNotFound) {
                // No cache exists yet, return empty manifest
                return CacheManifest.init(allocator);
            }
            return err;
        };
        defer file.close();

        const content = try file.readToEndAlloc(allocator, 10 * 1024 * 1024); // 10MB max
        defer allocator.free(content);

        return try parseManifest(allocator, content);
    }

    /// Save cache manifest to file
    fn save(self: *const CacheManifest, allocator: std.mem.Allocator, cache_path: []const u8) !void {
        const json_str = try serializeManifest(allocator, self);
        defer allocator.free(json_str);

        // Ensure .zig-cache directory exists
        const dir_path = std.fs.path.dirname(cache_path) orelse ".zig-cache";
        try std.fs.cwd().makePath(dir_path);

        const file = try std.fs.cwd().createFile(cache_path, .{});
        defer file.close();

        try file.writeAll(json_str);
    }
};

/// Parse JSON cache manifest
fn parseManifest(allocator: std.mem.Allocator, json_str: []const u8) !CacheManifest {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_str, .{});
    defer parsed.deinit();

    var manifest = CacheManifest.init(allocator);
    errdefer manifest.deinit(allocator);

    const root = parsed.value.object;
    const version = @as(u32, @intCast(root.get("version").?.integer));
    manifest.version = version;

    const entries_obj = root.get("entries").?.object;
    var entries_it = entries_obj.iterator();
    while (entries_it.next()) |kv| {
        const entry_obj = kv.value_ptr.object;

        const source_path = try allocator.dupe(u8, entry_obj.get("source_path").?.string);
        errdefer allocator.free(source_path);

        const hash_hex = entry_obj.get("content_hash").?.string;
        var content_hash: [32]u8 = undefined;
        _ = try std.fmt.hexToBytes(&content_hash, hash_hex);

        const mtime_ns = entry_obj.get("mtime_ns").?.integer;

        const class_names_arr = entry_obj.get("class_names").?.array;
        const class_names = try allocator.alloc([]const u8, class_names_arr.items.len);
        errdefer allocator.free(class_names);
        for (class_names_arr.items, 0..) |item, i| {
            class_names[i] = try allocator.dupe(u8, item.string);
        }

        const parent_names_arr = entry_obj.get("parent_names").?.array;
        const parent_names = try allocator.alloc([]const u8, parent_names_arr.items.len);
        errdefer allocator.free(parent_names);
        for (parent_names_arr.items, 0..) |item, i| {
            parent_names[i] = try allocator.dupe(u8, item.string);
        }

        const entry = CacheEntry{
            .source_path = source_path,
            .content_hash = content_hash,
            .mtime_ns = mtime_ns,
            .class_names = class_names,
            .parent_names = parent_names,
        };

        const key = try allocator.dupe(u8, kv.key_ptr.*);
        try manifest.entries.put(key, entry);
    }

    return manifest;
}

/// Write a JSON-escaped string
fn writeJsonString(writer: anytype, str: []const u8) !void {
    try writer.writeByte('"');
    for (str) |c| {
        switch (c) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            else => try writer.writeByte(c),
        }
    }
    try writer.writeByte('"');
}

/// Serialize cache manifest to JSON
fn serializeManifest(allocator: std.mem.Allocator, manifest: *const CacheManifest) ![]const u8 {
    var json_buf = std.ArrayList(u8){};
    errdefer json_buf.deinit(allocator);

    var writer = json_buf.writer(allocator);

    try writer.writeAll("{\"version\":");
    try writer.print("{d}", .{manifest.version});
    try writer.writeAll(",\"entries\":{");

    var first = true;
    var it = manifest.entries.iterator();
    while (it.next()) |kv| {
        if (!first) try writer.writeAll(",");
        first = false;

        try writeJsonString(writer, kv.key_ptr.*);
        try writer.writeAll(":{");

        try writer.writeAll("\"source_path\":");
        try writeJsonString(writer, kv.value_ptr.source_path);

        try writer.writeAll(",\"content_hash\":\"");
        for (kv.value_ptr.content_hash) |byte| {
            try writer.print("{x:0>2}", .{byte});
        }
        try writer.writeAll("\"");

        try writer.writeAll(",\"mtime_ns\":");
        try writer.print("{d}", .{kv.value_ptr.mtime_ns});

        try writer.writeAll(",\"class_names\":[");
        for (kv.value_ptr.class_names, 0..) |name, i| {
            if (i > 0) try writer.writeAll(",");
            try writeJsonString(writer, name);
        }
        try writer.writeAll("]");

        try writer.writeAll(",\"parent_names\":[");
        for (kv.value_ptr.parent_names, 0..) |name, i| {
            if (i > 0) try writer.writeAll(",");
            try writeJsonString(writer, name);
        }
        try writer.writeAll("]");

        try writer.writeAll("}");
    }

    try writer.writeAll("}}");

    return json_buf.toOwnedSlice(allocator);
}

/// Compute SHA-256 hash of file content
fn computeContentHash(content: []const u8) [32]u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update(content);
    var hash: [32]u8 = undefined;
    hasher.final(&hash);
    return hash;
}

/// Get file modification time in nanoseconds
fn getFileMtime(file_path: []const u8) !i128 {
    const stat = try std.fs.cwd().statFile(file_path);
    return stat.mtime;
}

/// Check if a file needs regeneration based on cache
fn needsRegeneration(
    allocator: std.mem.Allocator,
    source_path: []const u8,
    source_content: []const u8,
    cache_entry: ?CacheEntry,
) !bool {
    // If no cache entry exists, definitely need to regenerate
    if (cache_entry == null) return true;

    const entry = cache_entry.?;

    // Check timestamp first (fast check)
    const current_mtime = try getFileMtime(source_path);
    if (current_mtime != entry.mtime_ns) {
        // Timestamp changed, check content hash
        const current_hash = computeContentHash(source_content);
        if (!std.mem.eql(u8, &current_hash, &entry.content_hash)) {
            // Content actually changed
            return true;
        }
        // Timestamp changed but content is same (e.g., git checkout)
        // Still regenerate to update timestamp in cache
        return true;
    }

    // Timestamp unchanged, assume file is unchanged
    _ = allocator;
    return false;
}

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

                // Free doc comments in fields
                for (class_info.fields) |field| {
                    if (field.doc_comment) |doc| {
                        self.allocator.free(doc);
                    }
                }
                self.allocator.free(class_info.fields);

                // Free doc comments in methods
                for (class_info.methods) |method| {
                    if (method.doc_comment) |doc| {
                        self.allocator.free(doc);
                    }
                }
                self.allocator.free(class_info.methods);

                // Free doc comments in properties
                for (class_info.properties) |prop| {
                    if (prop.doc_comment) |doc| {
                        self.allocator.free(doc);
                    }
                }
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

    /// Build a map of class name -> list of descendant class names
    /// This includes both direct children and all transitive descendants
    fn buildDescendantMap(self: *GlobalRegistry) !std.StringHashMap(std.ArrayList([]const u8)) {
        var descendant_map = std.StringHashMap(std.ArrayList([]const u8)).init(self.allocator);
        errdefer {
            var it = descendant_map.iterator();
            while (it.next()) |entry| {
                entry.value_ptr.deinit(self.allocator);
            }
            descendant_map.deinit();
        }

        // First pass: collect direct children
        var file_it = self.files.iterator();
        while (file_it.next()) |file_entry| {
            for (file_entry.value_ptr.classes.items) |class_info| {
                if (class_info.parent_name) |parent_name| {
                    const gop = try descendant_map.getOrPut(parent_name);
                    if (!gop.found_existing) {
                        gop.value_ptr.* = .{};
                    }
                    try gop.value_ptr.append(self.allocator, class_info.name);
                }
            }
        }

        // Second pass: add transitive descendants
        // For each class, recursively add descendants of its children
        var class_names = std.ArrayList([]const u8){};
        defer class_names.deinit(self.allocator);

        var keys_it = descendant_map.keyIterator();
        while (keys_it.next()) |key| {
            try class_names.append(self.allocator, key.*);
        }

        for (class_names.items) |class_name| {
            var all_descendants = std.ArrayList([]const u8){};
            defer all_descendants.deinit(self.allocator);

            try collectAllDescendants(self.allocator, class_name, &descendant_map, &all_descendants);

            // Update the map with all descendants
            const existing = descendant_map.getPtr(class_name).?;
            existing.deinit(self.allocator);
            existing.* = try all_descendants.clone(self.allocator);
        }

        return descendant_map;
    }

    /// Helper to recursively collect all descendants of a class
    fn collectAllDescendants(
        allocator: std.mem.Allocator,
        class_name: []const u8,
        descendant_map: *std.StringHashMap(std.ArrayList([]const u8)),
        result: *std.ArrayList([]const u8),
    ) !void {
        const direct_children = descendant_map.get(class_name) orelse return;

        for (direct_children.items) |child| {
            // Add this child if not already in result
            var already_added = false;
            for (result.items) |existing| {
                if (std.mem.eql(u8, existing, child)) {
                    already_added = true;
                    break;
                }
            }
            if (!already_added) {
                try result.append(allocator, child);
                // Recursively add descendants of this child
                try collectAllDescendants(allocator, child, descendant_map, result);
            }
        }
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

            const file_info = self.files.get(current_file) orelse {
                return error.FileNotFound;
            };
            const imported_file = file_info.imports.get(import_alias) orelse {
                return null;
            };

            return self.getClass(imported_file, class_name);
        } else {
            const file_info = self.files.get(current_file) orelse {
                return error.FileNotFound;
            };

            const import_ref = file_info.imports.get(parent_ref);
            if (import_ref) |ref| {
                const ref_dot_pos = std.mem.lastIndexOfScalar(u8, ref, '.');
                if (ref_dot_pos) |ref_pos| {
                    const file_path = ref[0..ref_pos];
                    const class_name = ref[ref_pos + 1 ..];
                    return self.getClass(file_path, class_name);
                } else {
                    return self.getClass(ref, parent_ref);
                }
            } else {
                return self.getClass(current_file, parent_ref);
            }
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

        const line_end = std.mem.indexOfScalarPos(u8, source, quote_end, ';') orelse {
            pos = quote_end + 1;
            continue;
        };

        const full_line = source[line_start..line_end];

        if (std.mem.indexOf(u8, full_line, "const")) |const_pos| {
            const after_const = std.mem.trim(u8, full_line[const_pos + 5 ..], " \t");
            if (std.mem.indexOfScalar(u8, after_const, '=')) |eq_pos| {
                const alias = std.mem.trim(u8, after_const[0..eq_pos], " \t");
                const alias_owned = try allocator.dupe(u8, alias);
                errdefer allocator.free(alias_owned);

                const after_eq = std.mem.trim(u8, after_const[eq_pos + 1 ..], " \t");

                const resolved_ref = blk: {
                    if (std.mem.indexOf(u8, after_eq, ").")) |close_paren_dot| {
                        const class_name = std.mem.trim(u8, after_eq[close_paren_dot + 2 ..], " \t;");

                        const resolved_path: []const u8 = if (std.fs.path.dirname(current_file)) |dir|
                            try std.fs.path.join(allocator, &.{ dir, import_path })
                        else
                            try allocator.dupe(u8, import_path);
                        defer allocator.free(resolved_path);

                        break :blk try std.fmt.allocPrint(allocator, "{s}.{s}", .{ resolved_path, class_name });
                    } else {
                        if (std.fs.path.dirname(current_file)) |dir| {
                            break :blk try std.fs.path.join(allocator, &.{ dir, import_path });
                        } else {
                            break :blk try allocator.dupe(u8, import_path);
                        }
                    }
                };
                errdefer allocator.free(resolved_ref);

                const gop = try imports.getOrPut(alias_owned);
                if (gop.found_existing) {
                    // Duplicate alias - this shouldn't happen in valid Zig code,
                    // but if it does, we free the new allocations and keep existing
                    allocator.free(alias_owned);
                    allocator.free(resolved_ref);
                } else {
                    // New entry - store the value (key already set by getOrPut)
                    gop.value_ptr.* = resolved_ref;
                }
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
        // Find next zoop.class( or zoop.mixin(
        const class_start = std.mem.indexOfPos(u8, source, pos, "zoop.class(");
        const mixin_start = std.mem.indexOfPos(u8, source, pos, "zoop.mixin(");

        const next_start = blk: {
            if (class_start) |c| {
                if (mixin_start) |m| {
                    break :blk @min(c, m);
                }
                break :blk c;
            } else if (mixin_start) |m| {
                break :blk m;
            } else {
                break;
            }
        };

        if (try parseClassDefinition(allocator, source, next_start)) |parsed| {
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

            // Deep copy methods with their doc comments
            const methods_copy = try allocator.alloc(MethodDef, parsed.methods.len);
            for (parsed.methods, 0..) |method, i| {
                methods_copy[i] = MethodDef{
                    .name = method.name,
                    .source = method.source,
                    .signature = method.signature,
                    .return_type = method.return_type,
                    .is_static = method.is_static,
                    .doc_comment = if (method.doc_comment) |doc| try allocator.dupe(u8, doc) else null,
                };
            }

            // Deep copy fields with their doc comments
            const fields_copy = try allocator.alloc(FieldDef, parsed.fields.len);
            for (parsed.fields, 0..) |field, i| {
                fields_copy[i] = FieldDef{
                    .name = field.name,
                    .type_name = field.type_name,
                    .default_value = field.default_value,
                    .estimated_size = field.estimated_size,
                    .doc_comment = if (field.doc_comment) |doc| try allocator.dupe(u8, doc) else null,
                };
            }

            // Deep copy properties with their doc comments
            const properties_copy = try allocator.alloc(PropertyDef, parsed.properties.len);
            for (parsed.properties, 0..) |prop, i| {
                properties_copy[i] = PropertyDef{
                    .name = prop.name,
                    .type_name = prop.type_name,
                    .access = prop.access,
                    .default_value = prop.default_value,
                    .doc_comment = if (prop.doc_comment) |doc| try allocator.dupe(u8, doc) else null,
                };
            }

            const class_info = ClassInfo{
                .name = interned_name,
                .parent_name = interned_parent,
                .mixin_names = interned_mixins,
                .fields = fields_copy,
                .methods = methods_copy,
                .properties = properties_copy,
                .source_start = parsed.source_start,
                .source_end = parsed.source_end,
                .file_path = file_path,
            };

            try classes.append(allocator, class_info);
            pos = parsed.source_end;
        } else {
            pos = next_start + 1;
        }
    }
}

/// Strip trailing doc comments (///) from the end of source text.
/// This is used to avoid duplicating class-level doc comments.
fn stripTrailingDocComments(source: []const u8) []const u8 {
    if (source.len == 0) return source;

    var end = source.len;

    // Walk backwards through lines
    while (end > 0) {
        // Skip trailing newline if present
        var line_end = end;
        if (line_end > 0 and source[line_end - 1] == '\n') {
            line_end -= 1;
        }
        if (line_end > 0 and source[line_end - 1] == '\r') {
            line_end -= 1;
        }

        // Find start of current line
        var line_start = line_end;
        while (line_start > 0 and source[line_start - 1] != '\n' and source[line_start - 1] != '\r') {
            line_start -= 1;
        }

        // Prevent infinite loop - ensure we're making progress
        if (line_end <= 0 or line_start >= end) break;

        const line = std.mem.trim(u8, source[line_start..line_end], " \t");

        if (std.mem.startsWith(u8, line, "///")) {
            // This is a doc comment, remove it (including its newline)
            end = line_start;
        } else if (line.len == 0) {
            // Empty line, remove it and continue
            end = line_start;
        } else {
            // Non-doc-comment, non-empty line - stop
            break;
        }
    }

    return source[0..end];
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
        // Find next zoop.class( or zoop.mixin(
        const class_start = std.mem.indexOfPos(u8, source, pos, "zoop.class(");
        const mixin_start = std.mem.indexOfPos(u8, source, pos, "zoop.mixin(");

        const next_start = blk: {
            if (class_start) |c| {
                if (mixin_start) |m| {
                    break :blk @min(c, m);
                }
                break :blk c;
            } else if (mixin_start) |m| {
                break :blk m;
            } else {
                break;
            }
        };

        const class_keyword_start = blk: {
            var i = next_start;
            while (i > last_class_end) : (i -= 1) {
                if (source[i] == '\n' or i == last_class_end) {
                    const line_start = if (source[i] == '\n') i + 1 else i;
                    const line = std.mem.trim(u8, source[line_start..next_start], " \t");
                    if (std.mem.startsWith(u8, line, "pub const") or std.mem.startsWith(u8, line, "const")) {
                        break :blk line_start;
                    }
                }
            }
            break :blk next_start;
        };

        // Ensure we don't go backwards
        const safe_start = @max(last_class_end, class_keyword_start);
        const raw_segment = source[last_class_end..safe_start];
        // Strip trailing doc comments to avoid duplication (we emit them separately)
        const segment_no_docs = stripTrailingDocComments(raw_segment);
        const segment = try filterZoopImport(allocator, segment_no_docs);
        defer allocator.free(segment);
        try output.appendSlice(allocator, segment);

        if (try parseClassDefinition(allocator, source, next_start)) |parsed| {
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
            pos = next_start + 1;
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

/// Extract doc comment (///) before a declaration at the given position.
/// Searches backward from pos to find contiguous /// lines.
/// Returns the doc comment text without the /// prefix, or null if none found.
fn extractDocComment(source: []const u8, pos: usize, allocator: std.mem.Allocator) !?[]const u8 {
    if (pos == 0) return null;

    // Find the start of the line containing pos
    var line_start = pos;
    while (line_start > 0 and source[line_start - 1] != '\n') {
        line_start -= 1;
    }

    // Collect doc comment lines going backwards
    var doc_lines: std.ArrayList([]const u8) = .empty;
    defer doc_lines.deinit(allocator);

    var search_pos = line_start;
    while (search_pos > 0) {
        // Find previous line start
        const prev_line_end = search_pos - 1;
        if (prev_line_end == 0 or source[prev_line_end] != '\n') break;

        var prev_line_start = prev_line_end;
        while (prev_line_start > 0 and source[prev_line_start - 1] != '\n') {
            prev_line_start -= 1;
        }

        const prev_line = std.mem.trim(u8, source[prev_line_start..prev_line_end], " \t\r");

        // Check if it's a doc comment line
        if (std.mem.startsWith(u8, prev_line, "///")) {
            const comment_text = std.mem.trimLeft(u8, prev_line[3..], " \t");
            try doc_lines.insert(allocator, 0, comment_text);
            search_pos = prev_line_start;
        } else if (prev_line.len == 0) {
            // Empty line - continue looking
            search_pos = prev_line_start;
        } else {
            // Non-doc-comment, non-empty line - stop
            break;
        }
    }

    if (doc_lines.items.len == 0) return null;

    // Join lines with newlines
    var result: std.ArrayList(u8) = .empty;
    errdefer result.deinit(allocator);

    for (doc_lines.items, 0..) |line, i| {
        if (i > 0) try result.append(allocator, '\n');
        try result.appendSlice(allocator, line);
    }

    return try result.toOwnedSlice(allocator);
}

/// Extract file-level doc comment (//!) at the start of the file.
/// Returns the doc comment text without the //! prefix, or null if none found.
fn extractFileDocComment(source: []const u8, allocator: std.mem.Allocator) !?[]const u8 {
    var doc_lines: std.ArrayList([]const u8) = .empty;
    defer doc_lines.deinit(allocator);

    var pos: usize = 0;
    while (pos < source.len) {
        // Find line end
        const line_end = std.mem.indexOfScalarPos(u8, source, pos, '\n') orelse source.len;
        const line = std.mem.trim(u8, source[pos..line_end], " \t\r");

        if (std.mem.startsWith(u8, line, "//!")) {
            const comment_text = std.mem.trimLeft(u8, line[3..], " \t");
            try doc_lines.append(allocator, comment_text);
        } else if (line.len > 0) {
            // Non-doc-comment, non-empty line - stop
            break;
        }

        pos = if (line_end < source.len) line_end + 1 else source.len;
    }

    if (doc_lines.items.len == 0) return null;

    // Join lines with newlines
    var result: std.ArrayList(u8) = .empty;
    errdefer result.deinit(allocator);

    for (doc_lines.items, 0..) |line, i| {
        if (i > 0) try result.append(allocator, '\n');
        try result.appendSlice(allocator, line);
    }

    return try result.toOwnedSlice(allocator);
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
    class_doc: ?[]const u8,

    fn deinit(self: *@This()) void {
        for (self.mixin_names) |mixin| {
            self.allocator.free(mixin);
        }
        self.allocator.free(self.mixin_names);

        // Free doc comments in fields
        for (self.fields) |field| {
            if (field.doc_comment) |doc| {
                self.allocator.free(doc);
            }
        }
        self.allocator.free(self.fields);

        // Free doc comments in methods
        for (self.methods) |method| {
            if (method.doc_comment) |doc| {
                self.allocator.free(doc);
            }
        }
        self.allocator.free(self.methods);

        // Free doc comments in properties
        for (self.properties) |prop| {
            if (prop.doc_comment) |doc| {
                self.allocator.free(doc);
            }
        }
        self.allocator.free(self.properties);

        if (self.class_doc) |doc| {
            self.allocator.free(doc);
        }
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

    // Extract class-level doc comment (before the class declaration)
    const class_doc = try extractDocComment(source, name_start, allocator);

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
        .class_doc = class_doc,
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

        if (std.mem.startsWith(u8, body[pos..], "pub inline fn ") or
            std.mem.startsWith(u8, body[pos..], "pub fn ") or
            std.mem.startsWith(u8, body[pos..], "inline fn ") or
            std.mem.startsWith(u8, body[pos..], "fn "))
        {
            const fn_start = pos;
            const fn_keyword = if (std.mem.startsWith(u8, body[pos..], "pub inline fn "))
                "pub inline fn "
            else if (std.mem.startsWith(u8, body[pos..], "pub fn "))
                "pub fn "
            else if (std.mem.startsWith(u8, body[pos..], "inline fn "))
                "inline fn "
            else
                "fn ";
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

            // Extract doc comment before the method
            const doc_comment = try extractDocComment(body, fn_start, allocator);

            try methods.append(allocator, .{
                .name = method_name,
                .source = method_source,
                .signature = signature,
                .return_type = return_type_section,
                .doc_comment = doc_comment,
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

                    // Extract doc comment before the field
                    const field_doc = try extractDocComment(body, pos, allocator);

                    try fields.append(allocator, .{
                        .name = field_name,
                        .type_name = field_type,
                        .default_value = null,
                        .doc_comment = field_doc,
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

/// Generate a smart init function that takes parent args + child fields
fn generateSmartInit(
    allocator: std.mem.Allocator,
    class_name: []const u8,
    parent_init_source: []const u8,
    parent_type: []const u8,
    param_fields: []const FieldDef,
    param_properties: []const PropertyDef,
    all_fields: []const FieldDef,
    all_properties: []const PropertyDef,
) ![]const u8 {
    var result: std.ArrayList(u8) = .empty;
    defer result.deinit(allocator);

    const writer = result.writer(allocator);

    // Parse parent init signature
    // Example: "pub fn init(allocator: std.mem.Allocator, name_val: []const u8) !Parent {"
    const params_start = std.mem.indexOf(u8, parent_init_source, "(") orelse return error.InvalidInitSignature;
    const params_end = std.mem.indexOf(u8, parent_init_source, ")") orelse return error.InvalidInitSignature;
    const parent_params = parent_init_source[params_start + 1 .. params_end];

    // Extract return type (handle error unions like "!Parent")
    // Find the closing paren, then look for the return type before "{"
    const return_type_start = params_end + 1;
    const brace_pos = std.mem.indexOf(u8, parent_init_source[return_type_start..], "{") orelse return error.InvalidInitSignature;
    const return_type_section = std.mem.trim(u8, parent_init_source[return_type_start .. return_type_start + brace_pos], " \t\r\n");

    // Extract error union prefix (! or !!) if present
    var error_prefix: []const u8 = "";
    if (std.mem.startsWith(u8, return_type_section, "!!")) {
        error_prefix = "!!";
    } else if (std.mem.startsWith(u8, return_type_section, "!")) {
        error_prefix = "!";
    }

    // Build a map from field/prop name to parameter name
    // Parse parent params to extract "name: type" pairs
    var param_name_map = std.StringHashMap([]const u8).init(allocator);
    defer param_name_map.deinit();

    // Parse params string to find matching field types
    // This is a simplified parser - looks for "name: Type" patterns
    var param_iter = std.mem.tokenizeAny(u8, parent_params, ",");
    while (param_iter.next()) |param_decl| {
        const trimmed = std.mem.trim(u8, param_decl, " \t\r\n");
        if (std.mem.indexOf(u8, trimmed, ":")) |colon_pos| {
            const param_name = std.mem.trim(u8, trimmed[0..colon_pos], " \t\r\n");
            const param_type = std.mem.trim(u8, trimmed[colon_pos + 1 ..], " \t\r\n");

            // Try to match against fields
            for (all_fields) |field| {
                if (std.mem.eql(u8, field.type_name, param_type)) {
                    // Heuristic: if param ends with "_val" and field name matches prefix, map them
                    // e.g., "name_val" → "name"
                    if (std.mem.endsWith(u8, param_name, "_val")) {
                        const field_prefix = param_name[0 .. param_name.len - 4];
                        if (std.mem.eql(u8, field.name, field_prefix)) {
                            try param_name_map.put(field.name, param_name);
                            continue;
                        }
                    }
                    // Otherwise, if types match and names are similar, map directly
                    if (std.mem.eql(u8, field.name, param_name)) {
                        try param_name_map.put(field.name, param_name);
                    }
                }
            }
        }
    }

    // Generate signature: pub fn init(allocator, parent_params, field1: Type1, ...) !ClassName {
    try writer.writeAll("pub fn init(");

    // Always include allocator as first parameter
    try writer.writeAll("allocator: std.mem.Allocator");

    // Add parent params (skip allocator if it's already in parent params)
    if (parent_params.len > 0) {
        // Check if parent_params starts with "allocator:"
        if (!std.mem.startsWith(u8, std.mem.trim(u8, parent_params, " \t"), "allocator:")) {
            try writer.writeAll(", ");
            try writer.writeAll(parent_params);
        } else {
            // Parent already has allocator, skip it
            const comma_pos = std.mem.indexOf(u8, parent_params, ",");
            if (comma_pos) |pos| {
                try writer.writeAll(parent_params[pos..]);
            }
        }
    }

    // Add parameters for fields that need to be passed
    for (param_fields) |field| {
        try writer.writeAll(", ");
        try writer.print("{s}: {s}", .{ field.name, field.type_name });
    }

    // Add parameters for properties
    for (param_properties) |prop| {
        try writer.writeAll(", ");
        try writer.print("{s}: {s}", .{ prop.name, prop.type_name });
    }

    // Always return error union (for dynamic allocations)
    try writer.print(") !{s} {{\n", .{class_name});

    // Check if parent's init uses initFields pattern: "return try Parent.initFields("
    const body_start = std.mem.indexOf(u8, parent_init_source, "{") orelse return error.InvalidInitSignature;
    const body_end = std.mem.lastIndexOf(u8, parent_init_source, "}") orelse return error.InvalidInitSignature;
    const parent_body = parent_init_source[body_start + 1 .. body_end];

    const initfields_pattern = try std.fmt.allocPrint(allocator, "{s}.initFields(", .{parent_type});
    defer allocator.free(initfields_pattern);

    if (std.mem.indexOf(u8, parent_body, initfields_pattern)) |_| {
        // Parent uses initFields pattern
        // We need to:
        // 1. Copy everything before the initFields struct literal
        // 2. Extend the struct literal with child's additional fields
        // 3. Copy everything after

        // First, rewrite type names in the entire body
        const rewritten_body = try rewriteMixinMethod(allocator, parent_body, parent_type, class_name);
        defer allocator.free(rewritten_body);

        // Find the struct literal in the initFields call: .{
        const rewritten_initfields_pattern = try std.fmt.allocPrint(allocator, "{s}.initFields(", .{class_name});
        defer allocator.free(rewritten_initfields_pattern);

        const rewritten_call_pos = std.mem.indexOf(u8, rewritten_body, rewritten_initfields_pattern) orelse {
            // Fallback if we can't find it
            try writer.writeAll(rewritten_body);
            try writer.writeAll("    }\n\n");

            // Still generate initFields for child - inline generation
            try writer.writeAll("    fn initFields(allocator: std.mem.Allocator, fields: *const struct {");
            for (all_fields) |field| {
                try writer.print(" {s}: {s},", .{ field.name, field.type_name });
            }
            for (all_properties) |prop| {
                try writer.print(" {s}: {s},", .{ prop.name, prop.type_name });
            }
            try writer.print(" }}) !{s} {{\n", .{class_name});
            try writer.print("        return {s}{{\n", .{class_name});
            try writer.writeAll("            .allocator = allocator,\n");
            for (all_fields) |field| {
                const needs_alloc = std.mem.eql(u8, field.type_name, "[]const u8") or std.mem.eql(u8, field.type_name, "[]u8");
                if (needs_alloc) {
                    try writer.print("            .{s} = try allocator.dupe(u8, fields.{s}),\n", .{ field.name, field.name });
                } else {
                    try writer.print("            .{s} = fields.{s},\n", .{ field.name, field.name });
                }
            }
            for (all_properties) |prop| {
                const needs_alloc = std.mem.eql(u8, prop.type_name, "[]const u8") or std.mem.eql(u8, prop.type_name, "[]u8");
                if (needs_alloc) {
                    try writer.print("            .{s} = try allocator.dupe(u8, fields.{s}),\n", .{ prop.name, prop.name });
                } else {
                    try writer.print("            .{s} = fields.{s},\n", .{ prop.name, prop.name });
                }
            }
            try writer.writeAll("        };\n");
            try writer.writeAll("    }");
            return try result.toOwnedSlice(allocator);
        };

        // Find the .{ after initFields(allocator,
        const after_call = rewritten_body[rewritten_call_pos + rewritten_initfields_pattern.len ..];
        const struct_lit_start = std.mem.indexOf(u8, after_call, ".{") orelse {
            // No struct literal found, just copy as-is
            try writer.writeAll(rewritten_body);
            try writer.writeAll("    }\n\n");

            // Generate initFields for child - inline
            try writer.writeAll("    fn initFields(allocator: std.mem.Allocator, fields: *const struct {");
            for (all_fields) |field| {
                try writer.print(" {s}: {s},", .{ field.name, field.type_name });
            }
            for (all_properties) |prop| {
                try writer.print(" {s}: {s},", .{ prop.name, prop.type_name });
            }
            try writer.print(" }}) !{s} {{\n", .{class_name});
            try writer.print("        return {s}{{\n", .{class_name});
            try writer.writeAll("            .allocator = allocator,\n");
            for (all_fields) |field| {
                const needs_alloc = std.mem.eql(u8, field.type_name, "[]const u8") or std.mem.eql(u8, field.type_name, "[]u8");
                if (needs_alloc) {
                    try writer.print("            .{s} = try allocator.dupe(u8, fields.{s}),\n", .{ field.name, field.name });
                } else {
                    try writer.print("            .{s} = fields.{s},\n", .{ field.name, field.name });
                }
            }
            for (all_properties) |prop| {
                const needs_alloc = std.mem.eql(u8, prop.type_name, "[]const u8") or std.mem.eql(u8, prop.type_name, "[]u8");
                if (needs_alloc) {
                    try writer.print("            .{s} = try allocator.dupe(u8, fields.{s}),\n", .{ prop.name, prop.name });
                } else {
                    try writer.print("            .{s} = fields.{s},\n", .{ prop.name, prop.name });
                }
            }
            try writer.writeAll("        };\n");
            try writer.writeAll("    }");
            return try result.toOwnedSlice(allocator);
        };

        // Find the closing } of the struct literal (before the );)
        var brace_count: i32 = 1;
        var search_pos = struct_lit_start + 2; // Start after ".{"
        const struct_lit_end = blk: {
            while (search_pos < after_call.len) : (search_pos += 1) {
                if (after_call[search_pos] == '{') {
                    brace_count += 1;
                } else if (after_call[search_pos] == '}') {
                    brace_count -= 1;
                    if (brace_count == 0) break :blk search_pos;
                }
            }
            // Couldn't find closing brace
            try writer.writeAll(rewritten_body);
            try writer.writeAll("    }\n\n");

            // Generate initFields for child - inline
            try writer.writeAll("    fn initFields(allocator: std.mem.Allocator, fields: *const struct {");
            for (all_fields) |field| {
                try writer.print(" {s}: {s},", .{ field.name, field.type_name });
            }
            for (all_properties) |prop| {
                try writer.print(" {s}: {s},", .{ prop.name, prop.type_name });
            }
            try writer.print(" }}) !{s} {{\n", .{class_name});
            try writer.print("        return {s}{{\n", .{class_name});
            try writer.writeAll("            .allocator = allocator,\n");
            for (all_fields) |field| {
                const needs_alloc = std.mem.eql(u8, field.type_name, "[]const u8") or std.mem.eql(u8, field.type_name, "[]u8");
                if (needs_alloc) {
                    try writer.print("            .{s} = try allocator.dupe(u8, fields.{s}),\n", .{ field.name, field.name });
                } else {
                    try writer.print("            .{s} = fields.{s},\n", .{ field.name, field.name });
                }
            }
            for (all_properties) |prop| {
                const needs_alloc = std.mem.eql(u8, prop.type_name, "[]const u8") or std.mem.eql(u8, prop.type_name, "[]u8");
                if (needs_alloc) {
                    try writer.print("            .{s} = try allocator.dupe(u8, fields.{s}),\n", .{ prop.name, prop.name });
                } else {
                    try writer.print("            .{s} = fields.{s},\n", .{ prop.name, prop.name });
                }
            }
            try writer.writeAll("        };\n");
            try writer.writeAll("    }");
            return try result.toOwnedSlice(allocator);
        };

        // Copy everything up to (but not including) the struct literal closing }
        var content_before_close = rewritten_call_pos + rewritten_initfields_pattern.len + struct_lit_end;

        // Trim trailing comma and whitespace before the closing }
        while (content_before_close > 0) {
            const idx = content_before_close - 1;
            const c = rewritten_body[idx];
            if (c == ',' or c == ' ' or c == '\t' or c == '\n' or c == '\r') {
                content_before_close -= 1;
            } else {
                break;
            }
        }

        // Copy everything before the struct literal, ensuring we have &.{ syntax
        const before_struct_lit = rewritten_call_pos + rewritten_initfields_pattern.len + struct_lit_start;

        // Check if there's already a & before the .{
        const has_ampersand = before_struct_lit > 0 and rewritten_body[before_struct_lit - 1] == '&';

        if (has_ampersand) {
            // Already has &, just copy everything including &.{
            try writer.writeAll(rewritten_body[0 .. before_struct_lit + 2]); // Include "&.{"
        } else {
            // No &, add it
            try writer.writeAll(rewritten_body[0..before_struct_lit]);
            try writer.writeAll("&.{");
        }

        // Copy from after .{ (or &.{) to before closing }
        const after_struct_lit_open = before_struct_lit + 2; // Skip past ".{"
        try writer.writeAll(rewritten_body[after_struct_lit_open..content_before_close]);

        // Add child's additional fields to the struct literal
        if (param_fields.len > 0 or param_properties.len > 0) {
            for (param_fields) |field| {
                try writer.print(",\n            .{s} = {s}", .{ field.name, field.name });
            }
            for (param_properties) |prop| {
                try writer.print(",\n            .{s} = {s}", .{ prop.name, prop.name });
            }
        }

        // Copy the rest (starting from the closing } of the struct literal)
        const copy_end = rewritten_call_pos + rewritten_initfields_pattern.len + struct_lit_end;
        try writer.writeAll(rewritten_body[copy_end..]);
        try writer.writeAll("    }\n\n");

        // Generate child's initFields with struct parameter for all fields
        try writer.writeAll("    fn initFields(allocator: std.mem.Allocator, fields: *const struct {");

        // Add all fields to struct type
        for (all_fields) |field| {
            try writer.print(" {s}: {s},", .{ field.name, field.type_name });
        }
        for (all_properties) |prop| {
            try writer.print(" {s}: {s},", .{ prop.name, prop.type_name });
        }

        try writer.print(" }}) !{s} {{\n", .{class_name});
        try writer.print("        return {s}{{\n", .{class_name});
        try writer.writeAll("            .allocator = allocator,\n");

        // Initialize all fields from the struct parameter
        for (all_fields) |field| {
            const needs_alloc = std.mem.eql(u8, field.type_name, "[]const u8") or
                std.mem.eql(u8, field.type_name, "[]u8");

            if (needs_alloc) {
                try writer.print("            .{s} = try allocator.dupe(u8, fields.{s}),\n", .{ field.name, field.name });
            } else {
                try writer.print("            .{s} = fields.{s},\n", .{ field.name, field.name });
            }
        }

        for (all_properties) |prop| {
            const needs_alloc = std.mem.eql(u8, prop.type_name, "[]const u8") or
                std.mem.eql(u8, prop.type_name, "[]u8");

            if (needs_alloc) {
                try writer.print("            .{s} = try allocator.dupe(u8, fields.{s}),\n", .{ prop.name, prop.name });
            } else {
                try writer.print("            .{s} = fields.{s},\n", .{ prop.name, prop.name });
            }
        }

        try writer.writeAll("        };\n");
        try writer.writeAll("    }");

        return try result.toOwnedSlice(allocator);
    }

    // Parent doesn't use initFields - fall back to old behavior (extend struct literal)

    // Find the return statement in parent's body
    const return_pos = std.mem.lastIndexOf(u8, parent_body, "return") orelse {
        // No return statement found - just copy body and add return at end
        try writer.writeAll(parent_body);
        try writer.print("        return {s}{{\n", .{class_name});
        try writer.writeAll("            .allocator = allocator,\n");
        for (all_fields) |field| {
            try writer.print("            .{s} = {s},\n", .{ field.name, field.name });
        }
        for (all_properties) |prop| {
            try writer.print("            .{s} = {s},\n", .{ prop.name, prop.name });
        }
        try writer.writeAll("        };\n");
        try writer.writeAll("    }");
        return try result.toOwnedSlice(allocator);
    };

    // Find the struct literal in the return statement: return .{ or return Parent{
    const return_section = parent_body[return_pos..];
    const struct_init_start = blk: {
        if (std.mem.indexOf(u8, return_section, ".{")) |pos| {
            break :blk return_pos + pos + 2; // Position after ".{"
        } else if (std.mem.indexOf(u8, return_section, parent_type)) |type_pos| {
            if (std.mem.indexOf(u8, return_section[type_pos..], "{")) |open_brace| {
                break :blk return_pos + type_pos + open_brace + 1; // Position after "Parent{"
            }
        }
        // Couldn't find struct literal, fall back to simple generation
        try writer.writeAll(parent_body);
        try writer.writeAll("    }");
        return try result.toOwnedSlice(allocator);
    };

    // Find the closing brace of the struct literal
    var brace_count: i32 = 1;
    var pos = struct_init_start;
    const struct_init_end = blk: {
        while (pos < parent_body.len) : (pos += 1) {
            if (parent_body[pos] == '{') {
                brace_count += 1;
            } else if (parent_body[pos] == '}') {
                brace_count -= 1;
                if (brace_count == 0) break :blk pos;
            }
        }
        // Couldn't find closing brace
        try writer.writeAll(parent_body);
        try writer.writeAll("    }");
        return try result.toOwnedSlice(allocator);
    };

    // Copy everything before the struct literal's closing brace
    // But trim trailing comma/whitespace
    var content_end = struct_init_end;
    while (content_end > 0) : (content_end -= 1) {
        const c = parent_body[content_end - 1];
        if (c == ',' or c == ' ' or c == '\t' or c == '\n' or c == '\r') {
            continue;
        }
        break;
    }

    try writer.writeAll(parent_body[0..content_end]);

    // Add child's additional fields/properties
    for (param_fields) |field| {
        // Check if this is a string type that needs allocation
        const needs_alloc = std.mem.eql(u8, field.type_name, "[]const u8") or
            std.mem.eql(u8, field.type_name, "[]u8");

        if (needs_alloc) {
            try writer.print(",\n            .{s} = try allocator.dupe(u8, {s})", .{ field.name, field.name });
        } else {
            try writer.print(",\n            .{s} = {s}", .{ field.name, field.name });
        }
    }

    for (param_properties) |prop| {
        try writer.writeAll(",");

        // Check if this is a string type that needs allocation
        const needs_alloc = std.mem.eql(u8, prop.type_name, "[]const u8") or
            std.mem.eql(u8, prop.type_name, "[]u8");

        if (needs_alloc) {
            try writer.print("\n            .{s} = try allocator.dupe(u8, {s})", .{ prop.name, prop.name });
        } else {
            try writer.print("\n            .{s} = {s}", .{ prop.name, prop.name });
        }
    }

    // Copy the rest of the parent body after the struct literal
    try writer.writeAll(parent_body[struct_init_end..]);
    try writer.writeAll("    }");

    return try result.toOwnedSlice(allocator);
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

    // Emit class-level doc comment if present
    if (parsed.class_doc) |doc| {
        var doc_lines = std.mem.splitScalar(u8, doc, '\n');
        while (doc_lines.next()) |line| {
            try writer.print("/// {s}\n", .{line});
        }
    }

    try writer.print("pub const {s} = struct {{\n", .{parsed.name});

    // Check if class already has allocator field
    const has_allocator_field = blk: {
        for (parsed.fields) |field| {
            if (std.mem.eql(u8, field.name, "allocator")) break :blk true;
        }
        break :blk false;
    };

    // Check if class needs an allocator (has string fields or read-write string properties)
    const needs_allocator = blk: {
        // Check own fields for strings
        for (parsed.fields) |field| {
            if (std.mem.eql(u8, field.type_name, "[]const u8") or std.mem.eql(u8, field.type_name, "[]u8")) {
                break :blk true;
            }
        }
        // Check properties - only read-write ones need allocation
        for (parsed.properties) |prop| {
            const is_string_type = std.mem.eql(u8, prop.type_name, "[]const u8") or std.mem.eql(u8, prop.type_name, "[]u8");
            if (is_string_type and prop.access == .read_write) {
                break :blk true;
            }
        }
        break :blk false;
    };

    // Only add allocator if not already present AND class needs one
    if (!has_allocator_field and needs_allocator) {
        try writer.writeAll("    allocator: std.mem.Allocator,\n");

        // Separator if there are other fields
        if ((parsed.parent_name != null) or parsed.mixin_names.len > 0 or parsed.properties.len > 0 or parsed.fields.len > 0) {
            try writer.writeAll("\n");
        }
    }

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
        if (prop.doc_comment) |doc| {
            var doc_lines = std.mem.splitScalar(u8, doc, '\n');
            while (doc_lines.next()) |line| {
                try writer.print("    /// {s}\n", .{line});
            }
        }
        try writer.print("    {s}: {s},\n", .{ prop.name, prop.type_name });
    }

    for (parsed.fields) |field| {
        if (field.doc_comment) |doc| {
            var doc_lines = std.mem.splitScalar(u8, doc, '\n');
            while (doc_lines.next()) |line| {
                try writer.print("    /// {s}\n", .{line});
            }
        }
        try writer.print("    {s}: {s},\n", .{ field.name, field.type_name });
    }

    if (parsed.fields.len > 0 and parsed.methods.len > 0) {
        try writer.writeAll("\n");
    }

    // First, emit init and deinit if user defined them
    for (parsed.methods) |method| {
        if (std.mem.eql(u8, method.name, "init") or std.mem.eql(u8, method.name, "deinit")) {
            // Emit doc comment if present
            if (method.doc_comment) |doc| {
                var doc_lines = std.mem.splitScalar(u8, doc, '\n');
                while (doc_lines.next()) |line| {
                    try writer.print("    /// {s}\n", .{line});
                }
            }
            // Rename reserved parameters to avoid shadowing
            const renamed_source = try renameReservedParams(allocator, method.source);
            defer allocator.free(renamed_source);
            try writer.print("    {s}\n", .{renamed_source});
        }
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

        var parent_methods: std.ArrayList(ParentMethod) = .empty;
        defer parent_methods.deinit(allocator);

        var current_parent: ?[]const u8 = parent_ref;
        var current_file_path = current_file;

        while (current_parent) |parent| {
            const parent_info = (try registry.resolveParentReference(parent, current_file_path)) orelse {
                break;
            };

            for (parent_info.fields) |field| {
                try parent_field_names.put(field.name, {});
            }

            for (parent_info.properties) |prop| {
                try parent_field_names.put(prop.name, {});
            }

            for (parent_info.methods) |method| {
                // Skip methods that child has already defined (override detection)
                if (child_method_names.contains(method.name)) continue;

                // Skip static methods EXCEPT init and deinit
                const is_init_or_deinit = std.mem.eql(u8, method.name, "init") or std.mem.eql(u8, method.name, "deinit");
                if (method.is_static and !is_init_or_deinit) continue;

                // Copy all methods including init and deinit
                try parent_methods.append(allocator, .{
                    .method = method,
                    .parent_type = parent_info.name,
                });
            }

            current_parent = parent_info.parent_name;
            current_file_path = parent_info.file_path;
        }

        // Check if parent has init and capture it
        var parent_init_method: ?MethodDef = null;
        var parent_init_type: ?[]const u8 = null;
        for (parent_methods.items) |parent_method| {
            if (std.mem.eql(u8, parent_method.method.name, "init")) {
                parent_init_method = parent_method.method;
                parent_init_type = parent_method.parent_type;
                break;
            }
        }

        // If parent has init and child has fields/properties, generate smart init
        const need_smart_init = parent_init_method != null and (parsed.fields.len > 0 or parsed.properties.len > 0);

        // First emit init/deinit from parent if not generating smart init
        for (parent_methods.items) |parent_method| {
            const method = parent_method.method;
            const parent_type = parent_method.parent_type;

            // Skip parent's init if we're generating a smart init
            if (need_smart_init and std.mem.eql(u8, method.name, "init")) {
                continue;
            }

            // Only emit init/deinit in this pass
            if (std.mem.eql(u8, method.name, "init") or std.mem.eql(u8, method.name, "deinit")) {
                // Emit doc comment if present
                if (method.doc_comment) |doc| {
                    var doc_lines = std.mem.splitScalar(u8, doc, '\n');
                    while (doc_lines.next()) |line| {
                        try writer.print("    /// {s}\n", .{line});
                    }
                }
                // Copy and rewrite parent method
                const rewritten_method = try rewriteMixinMethod(allocator, method.source, parent_type, parsed.name);
                defer allocator.free(rewritten_method);

                try writer.print("    {s}\n", .{rewritten_method});
            }
        }

        // Generate smart init if needed
        if (need_smart_init) {
            // Find the topmost ancestor with init
            var topmost_init: ?MethodDef = null;
            var topmost_init_type: ?[]const u8 = null;
            var curr_parent: ?[]const u8 = parent_ref;
            var curr_file = current_file;

            while (curr_parent) |parent| {
                const parent_info = (try registry.resolveParentReference(parent, curr_file)) orelse break;

                // Check if this parent has init
                for (parent_info.methods) |method| {
                    if (std.mem.eql(u8, method.name, "init")) {
                        topmost_init = method;
                        topmost_init_type = parent_info.name;
                    }
                }

                curr_parent = parent_info.parent_name;
                curr_file = parent_info.file_path;
            }

            // Collect fields that need to be in init params
            // These are fields from ancestors without init + current class fields
            var init_param_fields: std.ArrayList(FieldDef) = .empty;
            defer init_param_fields.deinit(allocator);
            var init_param_props: std.ArrayList(PropertyDef) = .empty;
            defer init_param_props.deinit(allocator);

            // Walk hierarchy and collect fields from classes that don't have init
            curr_parent = parent_ref;
            curr_file = current_file;
            while (curr_parent) |parent| {
                const parent_info = (try registry.resolveParentReference(parent, curr_file)) orelse break;

                // Check if this parent has its own init
                var has_own_init = false;
                for (parent_info.methods) |method| {
                    if (std.mem.eql(u8, method.name, "init")) {
                        has_own_init = true;
                        break;
                    }
                }

                // If no init, need params for these fields
                if (!has_own_init) {
                    for (parent_info.fields) |field| {
                        try init_param_fields.append(allocator, field);
                    }
                    for (parent_info.properties) |prop| {
                        try init_param_props.append(allocator, prop);
                    }
                } else {
                    // Found parent with init, stop here
                    break;
                }

                curr_parent = parent_info.parent_name;
                curr_file = parent_info.file_path;
            }

            // Reverse to get correct order (ancestors first)
            std.mem.reverse(FieldDef, init_param_fields.items);
            std.mem.reverse(PropertyDef, init_param_props.items);

            // Add current class fields to params
            for (parsed.fields) |field| {
                try init_param_fields.append(allocator, field);
            }
            for (parsed.properties) |prop| {
                try init_param_props.append(allocator, prop);
            }

            // For initialization body, we need ALL fields (parent + current)
            // Collect all parent fields again
            var all_init_fields: std.ArrayList(FieldDef) = .empty;
            defer all_init_fields.deinit(allocator);
            var all_init_props: std.ArrayList(PropertyDef) = .empty;
            defer all_init_props.deinit(allocator);

            // Walk up entire parent hierarchy to collect all fields
            curr_parent = parent_ref;
            curr_file = current_file;
            while (curr_parent) |parent| {
                const parent_info = (try registry.resolveParentReference(parent, curr_file)) orelse break;

                for (parent_info.fields) |field| {
                    try all_init_fields.append(allocator, field);
                }
                for (parent_info.properties) |prop| {
                    try all_init_props.append(allocator, prop);
                }

                curr_parent = parent_info.parent_name;
                curr_file = parent_info.file_path;
            }

            // Reverse to get correct order (grandparent first)
            std.mem.reverse(FieldDef, all_init_fields.items);
            std.mem.reverse(PropertyDef, all_init_props.items);

            // Add current class fields
            for (parsed.fields) |field| {
                try all_init_fields.append(allocator, field);
            }
            for (parsed.properties) |prop| {
                try all_init_props.append(allocator, prop);
            }

            const smart_init = try generateSmartInit(
                allocator,
                parsed.name,
                topmost_init.?.source,
                topmost_init_type.?,
                init_param_fields.items,
                init_param_props.items,
                all_init_fields.items,
                all_init_props.items,
            );
            defer allocator.free(smart_init);
            try writer.print("    {s}\n", .{smart_init});
        }
    }

    // Generate default init if no init exists and class has fields
    {
        const has_init = blk: {
            for (parsed.methods) |method| {
                if (std.mem.eql(u8, method.name, "init")) break :blk true;
            }
            break :blk false;
        };

        const has_parent_init = parsed.parent_name != null and blk: {
            var curr_parent: ?[]const u8 = parsed.parent_name;
            var curr_file = current_file;
            while (curr_parent) |parent| {
                const parent_info = (try registry.resolveParentReference(parent, curr_file)) orelse break;
                for (parent_info.methods) |method| {
                    if (std.mem.eql(u8, method.name, "init")) break :blk true;
                }
                curr_parent = parent_info.parent_name;
                curr_file = parent_info.file_path;
            }
            break :blk false;
        };

        // Generate default init if no init exists (neither in this class nor inherited)
        if (!has_init and !has_parent_init) {
            // Collect ALL fields (parent + own) for init parameters
            var all_fields_for_init: std.ArrayList(FieldDef) = .empty;
            defer all_fields_for_init.deinit(allocator);
            var all_props_for_init: std.ArrayList(PropertyDef) = .empty;
            defer all_props_for_init.deinit(allocator);

            // Collect parent fields
            if (parsed.parent_name) |parent_ref| {
                var curr_parent: ?[]const u8 = parent_ref;
                var curr_file = current_file;
                while (curr_parent) |parent| {
                    const parent_info = (try registry.resolveParentReference(parent, curr_file)) orelse break;
                    for (parent_info.fields) |field| {
                        try all_fields_for_init.append(allocator, field);
                    }
                    for (parent_info.properties) |prop| {
                        try all_props_for_init.append(allocator, prop);
                    }
                    curr_parent = parent_info.parent_name;
                    curr_file = parent_info.file_path;
                }
                // Reverse to get correct order (grandparent first)
                std.mem.reverse(FieldDef, all_fields_for_init.items);
                std.mem.reverse(PropertyDef, all_props_for_init.items);
            }

            // Collect mixin fields
            for (parsed.mixin_names) |mixin_ref| {
                const mixin_info = (try registry.resolveParentReference(mixin_ref, current_file)) orelse continue;
                for (mixin_info.fields) |field| {
                    try all_fields_for_init.append(allocator, field);
                }
                for (mixin_info.properties) |prop| {
                    try all_props_for_init.append(allocator, prop);
                }
            }

            // Add own fields
            try all_fields_for_init.appendSlice(allocator, parsed.fields);
            try all_props_for_init.appendSlice(allocator, parsed.properties);

            // Check if we actually need init - only if there are fields or writable properties
            // Read-only properties alone don't need initialization
            const has_writable_props = blk: {
                for (all_props_for_init.items) |prop| {
                    if (prop.access == .read_write) break :blk true;
                }
                break :blk false;
            };

            const needs_init = all_fields_for_init.items.len > 0 or has_writable_props;

            // Only generate init if needed
            if (needs_init) {
                if (parsed.methods.len > 0) try writer.writeAll("\n");

                // Generate init that calls initFields
                try writer.writeAll("    pub fn init(allocator: std.mem.Allocator");

                // Add parameters for all fields
                for (all_fields_for_init.items) |field| {
                    try writer.print(", {s}: {s}", .{ field.name, field.type_name });
                }
                for (all_props_for_init.items) |prop| {
                    try writer.print(", {s}: {s}", .{ prop.name, prop.type_name });
                }

                try writer.print(") !{s} {{\n", .{parsed.name});
                try writer.print("        return try {s}.initFields(allocator, &.{{\n", .{parsed.name});

                // Pass all parameters to initFields
                var first = true;
                for (all_fields_for_init.items) |field| {
                    if (!first) try writer.writeAll(",\n");
                    try writer.print("            .{s} = {s}", .{ field.name, field.name });
                    first = false;
                }
                for (all_props_for_init.items) |prop| {
                    if (!first) try writer.writeAll(",\n");
                    try writer.print("            .{s} = {s}", .{ prop.name, prop.name });
                    first = false;
                }

                // Only add trailing comma if there are fields
                if (!first) {
                    try writer.writeAll(",\n        });\n");
                } else {
                    try writer.writeAll("\n        });\n");
                }
                try writer.writeAll("    }\n");

                // Generate initFields helper
                try writer.writeAll("    fn initFields(allocator: std.mem.Allocator, fields: *const struct {");

                // Add all fields to struct type
                for (all_fields_for_init.items) |field| {
                    try writer.print(" {s}: {s},", .{ field.name, field.type_name });
                }
                for (all_props_for_init.items) |prop| {
                    try writer.print(" {s}: {s},", .{ prop.name, prop.type_name });
                }

                try writer.print(" }}) !{s} {{\n", .{parsed.name});
                // If no fields, suppress unused parameter warning
                if (all_fields_for_init.items.len == 0 and all_props_for_init.items.len == 0) {
                    try writer.writeAll("        _ = fields;\n");
                }
                try writer.print("        return .{{\n", .{});

                // Only add allocator field if struct actually has one
                if (!has_allocator_field and needs_allocator) {
                    try writer.writeAll("            .allocator = allocator,\n");
                }

                // Initialize all fields (allocate strings only for non-borrowed data)
                for (all_fields_for_init.items) |field| {
                    // Fields always get allocated if they're string types (no read-only distinction for fields)
                    const needs_alloc = std.mem.eql(u8, field.type_name, "[]const u8") or
                        std.mem.eql(u8, field.type_name, "[]u8");
                    if (needs_alloc) {
                        try writer.print("            .{s} = try allocator.dupe(u8, fields.{s}),\n", .{ field.name, field.name });
                    } else {
                        try writer.print("            .{s} = fields.{s},\n", .{ field.name, field.name });
                    }
                }

                // Initialize properties (read-only properties are NOT allocated)
                for (all_props_for_init.items) |prop| {
                    // Read-only properties are borrowed, not owned - no allocation needed
                    const is_string_type = std.mem.eql(u8, prop.type_name, "[]const u8") or
                        std.mem.eql(u8, prop.type_name, "[]u8");
                    const needs_alloc = is_string_type and prop.access == .read_write;

                    if (needs_alloc) {
                        try writer.print("            .{s} = try allocator.dupe(u8, fields.{s}),\n", .{ prop.name, prop.name });
                    } else {
                        try writer.print("            .{s} = fields.{s},\n", .{ prop.name, prop.name });
                    }
                }

                try writer.writeAll("        };\n");
                try writer.writeAll("    }\n");
            } // end if (needs_init)
        }
    }

    // Generate deinit method to free dynamic fields (including inherited ones)
    // Track if deinit exists (user-written or generated)
    var has_deinit = false;
    for (parsed.methods) |method| {
        if (std.mem.eql(u8, method.name, "deinit")) {
            has_deinit = true;
            break;
        }
    }

    {
        // Collect all string fields that need freeing (from entire hierarchy)
        var string_fields: std.ArrayList([]const u8) = .empty;
        defer string_fields.deinit(allocator);

        // Collect parent string fields
        if (parsed.parent_name) |parent_ref| {
            var curr_parent: ?[]const u8 = parent_ref;
            var curr_file = current_file;

            // Walk up hierarchy to collect all string fields
            var all_parent_string_fields: std.ArrayList([]const u8) = .empty;
            defer all_parent_string_fields.deinit(allocator);

            while (curr_parent) |parent| {
                const parent_info = (try registry.resolveParentReference(parent, curr_file)) orelse break;

                for (parent_info.fields) |field| {
                    if (std.mem.eql(u8, field.type_name, "[]const u8") or std.mem.eql(u8, field.type_name, "[]u8")) {
                        try all_parent_string_fields.append(allocator, field.name);
                    }
                }
                for (parent_info.properties) |prop| {
                    // Only free read-write properties (read-only are borrowed, not owned)
                    const is_string_type = std.mem.eql(u8, prop.type_name, "[]const u8") or std.mem.eql(u8, prop.type_name, "[]u8");
                    if (is_string_type and prop.access == .read_write) {
                        try all_parent_string_fields.append(allocator, prop.name);
                    }
                }

                curr_parent = parent_info.parent_name;
                curr_file = parent_info.file_path;
            }

            // Reverse to get correct order
            std.mem.reverse([]const u8, all_parent_string_fields.items);
            try string_fields.appendSlice(allocator, all_parent_string_fields.items);
        }

        // Collect mixin string fields
        for (parsed.mixin_names) |mixin_ref| {
            const mixin_info = (try registry.resolveParentReference(mixin_ref, current_file)) orelse continue;
            for (mixin_info.fields) |field| {
                if (std.mem.eql(u8, field.type_name, "[]const u8") or std.mem.eql(u8, field.type_name, "[]u8")) {
                    try string_fields.append(allocator, field.name);
                }
            }
            for (mixin_info.properties) |prop| {
                // Only free read-write properties (read-only are borrowed, not owned)
                const is_string_type = std.mem.eql(u8, prop.type_name, "[]const u8") or std.mem.eql(u8, prop.type_name, "[]u8");
                if (is_string_type and prop.access == .read_write) {
                    try string_fields.append(allocator, prop.name);
                }
            }
        }

        // Add own string fields
        for (parsed.fields) |field| {
            if (std.mem.eql(u8, field.type_name, "[]const u8") or std.mem.eql(u8, field.type_name, "[]u8")) {
                try string_fields.append(allocator, field.name);
            }
        }
        for (parsed.properties) |prop| {
            // Only free read-write properties (read-only are borrowed, not owned)
            const is_string_type = std.mem.eql(u8, prop.type_name, "[]const u8") or std.mem.eql(u8, prop.type_name, "[]u8");
            if (is_string_type and prop.access == .read_write) {
                try string_fields.append(allocator, prop.name);
            }
        }

        if (string_fields.items.len > 0 and !has_deinit) {
            try writer.writeAll("    pub fn deinit(self: *");
            try writer.print("{s}) void {{\n", .{parsed.name});

            for (string_fields.items) |field_name| {
                try writer.print("        self.allocator.free(self.{s});\n", .{field_name});
            }

            try writer.writeAll("    }\n");
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

                // Skip static methods EXCEPT init and deinit
                const is_init_or_deinit = std.mem.eql(u8, method.name, "init") or std.mem.eql(u8, method.name, "deinit");
                if (method.is_static and !is_init_or_deinit) continue;

                // Emit doc comment if present
                if (method.doc_comment) |doc| {
                    var doc_lines = std.mem.splitScalar(u8, doc, '\n');
                    while (doc_lines.next()) |line| {
                        try writer.print("    /// {s}\n", .{line});
                    }
                }
                // Copy all methods including init/deinit (with type rewriting)
                const rewritten_method = try rewriteMixinMethod(allocator, method.source, mixin_info.name, parsed.name);
                defer allocator.free(rewritten_method);

                try writer.print("    {s}\n", .{rewritten_method});
            }
        }
    }

    // Emit other user methods (excluding init/deinit which were emitted earlier)
    for (parsed.methods) |method| {
        if (!std.mem.eql(u8, method.name, "init") and !std.mem.eql(u8, method.name, "deinit")) {
            // Emit doc comment if present
            if (method.doc_comment) |doc| {
                var doc_lines = std.mem.splitScalar(u8, doc, '\n');
                while (doc_lines.next()) |line| {
                    try writer.print("    /// {s}\n", .{line});
                }
            }
            // Rename reserved parameters to avoid shadowing
            const renamed_source = try renameReservedParams(allocator, method.source);
            defer allocator.free(renamed_source);
            try writer.print("    {s}\n", .{renamed_source});
        }
    }

    // Emit other parent methods (excluding init/deinit which were emitted earlier)
    if (parsed.parent_name) |parent_ref| {
        var parent_field_names_for_other_methods = std.StringHashMap(void).init(allocator);
        defer parent_field_names_for_other_methods.deinit();

        const ParentMethodForOther = struct {
            method: MethodDef,
            parent_type: []const u8,
        };

        var parent_methods_for_other: std.ArrayList(ParentMethodForOther) = .empty;
        defer parent_methods_for_other.deinit(allocator);

        var curr_parent: ?[]const u8 = parent_ref;
        var curr_file = current_file;

        while (curr_parent) |parent| {
            const parent_info = (try registry.resolveParentReference(parent, curr_file)) orelse break;

            for (parent_info.methods) |method| {
                // Skip if child already has this method
                if (child_method_names.contains(method.name)) continue;

                // Skip static methods EXCEPT init and deinit (but we already emitted those)
                const is_init_or_deinit = std.mem.eql(u8, method.name, "init") or std.mem.eql(u8, method.name, "deinit");
                if (method.is_static and !is_init_or_deinit) continue;
                if (is_init_or_deinit) continue; // Already emitted

                try parent_methods_for_other.append(allocator, .{
                    .method = method,
                    .parent_type = parent_info.name,
                });
            }

            curr_parent = parent_info.parent_name;
            curr_file = parent_info.file_path;
        }

        // Emit other parent methods
        for (parent_methods_for_other.items) |parent_method| {
            const method = parent_method.method;
            const parent_type = parent_method.parent_type;

            // Emit doc comment if present
            if (method.doc_comment) |doc| {
                var doc_lines = std.mem.splitScalar(u8, doc, '\n');
                while (doc_lines.next()) |line| {
                    try writer.print("    /// {s}\n", .{line});
                }
            }
            const rewritten_method = try rewriteMixinMethod(allocator, method.source, parent_type, parsed.name);
            defer allocator.free(rewritten_method);

            try writer.print("    {s}\n", .{rewritten_method});
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

/// Rename reserved parameter names (init, deinit) to avoid shadowing conflicts
/// E.g., "fn foo(init: Bar)" -> "fn foo(init_: Bar)" and renames all usages in body
fn renameReservedParams(
    allocator: std.mem.Allocator,
    method_source: []const u8,
) ![]u8 {
    const reserved_params = [_][]const u8{ "init", "deinit" };

    var result: []u8 = try allocator.dupe(u8, method_source);

    for (reserved_params) |param_name| {
        const new_result = try renameParameter(allocator, result, param_name);
        allocator.free(result);
        result = new_result;
    }

    return result;
}

/// Rename a specific parameter throughout a method
fn renameParameter(
    allocator: std.mem.Allocator,
    method_source: []const u8,
    param_name: []const u8,
) ![]u8 {
    const new_name = try std.fmt.allocPrint(allocator, "{s}_", .{param_name});
    defer allocator.free(new_name);

    // Find parameter list
    const fn_pos = std.mem.indexOf(u8, method_source, "fn ") orelse return try allocator.dupe(u8, method_source);
    const paren_start = std.mem.indexOfPos(u8, method_source, fn_pos, "(") orelse return try allocator.dupe(u8, method_source);
    const paren_end = findMatchingParen(method_source, paren_start) orelse return try allocator.dupe(u8, method_source);

    const param_list = method_source[paren_start .. paren_end + 1];

    // Check if parameter exists in param list with proper boundaries
    const search_pattern = try std.fmt.allocPrint(allocator, "{s}:", .{param_name});
    defer allocator.free(search_pattern);

    var param_found = false;
    var search_pos: usize = 0;
    while (std.mem.indexOfPos(u8, param_list, search_pos, search_pattern)) |found_pos| {
        // Check if it's a full identifier match
        const before_ok = found_pos == 0 or !isIdentifierChar(param_list[found_pos - 1]);
        if (before_ok) {
            param_found = true;
            break;
        }
        search_pos = found_pos + 1;
    }

    if (!param_found) {
        return try allocator.dupe(u8, method_source);
    }

    // Replace all occurrences of the parameter name throughout the method
    var result: std.ArrayList(u8) = .empty;
    errdefer result.deinit(allocator);

    var pos: usize = 0;
    var in_string = false;
    var in_comment = false;

    while (pos < method_source.len) {
        // Handle string literals
        if (in_string) {
            if (method_source[pos] == '"' and (pos == 0 or method_source[pos - 1] != '\\')) {
                in_string = false;
            }
            try result.append(allocator, method_source[pos]);
            pos += 1;
            continue;
        }

        // Handle comments
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

        // Check for parameter name with proper word boundaries
        if (std.mem.startsWith(u8, method_source[pos..], param_name)) {
            const before_ok = pos == 0 or !isIdentifierChar(method_source[pos - 1]);
            const after_pos = pos + param_name.len;
            const after_ok = after_pos >= method_source.len or !isIdentifierChar(method_source[after_pos]);

            if (before_ok and after_ok) {
                try result.appendSlice(allocator, new_name);
                pos += param_name.len;
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
