# Cross-File Inheritance Design

## Problem

Currently, `zoop-codegen` processes each file independently with its own registry:

```zig
// src/codegen.zig:182
fn processSourceFile(...) {
    var class_registry = std.StringHashMap(ClassInfo).init(allocator);
    defer class_registry.deinit();
    // ... process file ...
}
```

This means:
- Parent class must be in same file as child
- Cannot use `extends: parent.Parent` where `parent = @import("parent.zig")`

## Desired Behavior

```zig
// models/base.zig
pub const Entity = zoop.class(struct {
    id: u64,
    pub fn getId(self: *Entity) u64 { return self.id; }
});

// models/player.zig
const base = @import("base.zig");

pub const Player = zoop.class(struct {
    pub const extends = base.Entity;
    name: []const u8,
});

// Generated: models/player.zig
pub const Player = struct {
    super: base.Entity,  // ✅ Reference to imported type
    name: []const u8,
    
    pub inline fn call_getId(self: *Player) u64 {
        return self.super.getId();
    }
};
```

## Architecture

### Two-Pass Approach

**Pass 1: Scan All Files**
- Build global registry of all classes across all files
- Track which file each class is defined in
- Parse import statements to build import map
- Don't generate code yet

**Pass 2: Generate Code**
- Process files in dependency order (parents before children)
- Resolve parent references using global registry
- Generate code with correct imports

### Data Structures

```zig
const FileInfo = struct {
    path: []const u8,
    imports: std.StringHashMap([]const u8),  // alias -> file_path
    classes: []ClassInfo,
};

const GlobalRegistry = struct {
    allocator: std.mem.Allocator,
    files: std.StringHashMap(FileInfo),  // file_path -> FileInfo
    classes: std.StringHashMap(ClassLocation),  // class_name -> location
    
    const ClassLocation = struct {
        file_path: []const u8,
        class_info: ClassInfo,
    };
};
```

### Import Resolution

```zig
// Input: "pub const extends = base.Entity"
// Step 1: Extract "base.Entity"
// Step 2: Look up "base" in file's imports → "models/base.zig"
// Step 3: Look up "Entity" in "models/base.zig" registry
// Step 4: Return ClassInfo for Entity

fn resolveParentReference(
    parent_ref: []const u8,  // "base.Entity"
    current_file: []const u8,
    registry: *GlobalRegistry,
) !ClassInfo {
    // Split on '.'
    const dot_pos = std.mem.indexOfScalar(u8, parent_ref, '.');
    
    if (dot_pos) |pos| {
        // Qualified name: "base.Entity"
        const import_alias = parent_ref[0..pos];
        const class_name = parent_ref[pos + 1..];
        
        // Look up import alias
        const file_info = registry.files.get(current_file) orelse return error.FileNotFound;
        const imported_file = file_info.imports.get(import_alias) orelse return error.ImportNotFound;
        
        // Look up class in imported file
        const class_key = try std.fmt.allocPrint(registry.allocator, "{s}.{s}", .{imported_file, class_name});
        defer registry.allocator.free(class_key);
        
        return registry.classes.get(class_key) orelse error.ClassNotFound;
    } else {
        // Unqualified name: "Entity" (same file)
        const class_key = try std.fmt.allocPrint(registry.allocator, "{s}.{s}", .{current_file, parent_ref});
        defer registry.allocator.free(class_key);
        
        return registry.classes.get(class_key) orelse error.ClassNotFound;
    }
}
```

### File Processing Order

Use topological sort to ensure parents are processed before children:

```zig
fn computeProcessingOrder(registry: *GlobalRegistry) ![][]const u8 {
    var graph = DependencyGraph.init(registry.allocator);
    defer graph.deinit();
    
    // Build dependency graph
    var it = registry.files.iterator();
    while (it.next()) |entry| {
        const file_path = entry.key_ptr.*;
        
        for (entry.value_ptr.classes) |class_info| {
            if (class_info.parent_name) |parent_ref| {
                // Find parent's file
                const parent_class = try resolveParentReference(parent_ref, file_path, registry);
                const parent_file = parent_class.file_path;
                
                // Add edge: parent_file -> current_file
                try graph.addEdge(parent_file, file_path);
            }
        }
    }
    
    // Topological sort
    return try graph.topologicalSort();
}
```

## Implementation Plan

### Phase 1: Global Registry (3-4 hours)

1. Move ClassInfo to module level
2. Create GlobalRegistry struct
3. Modify `generateAllClasses()` to:
   - Pass 1: Scan all files, build global registry
   - Pass 2: Generate code using global registry

### Phase 2: Import Parsing (2-3 hours)

1. Parse `const x = @import("file.zig")` statements
2. Store import map per file
3. Handle both relative and absolute imports

### Phase 3: Parent Resolution (2-3 hours)

1. Implement `resolveParentReference()`
2. Support qualified names (`base.Entity`)
3. Support unqualified names (`Entity`)
4. Error handling for missing imports/classes

### Phase 4: Dependency Ordering (2-3 hours)

1. Build dependency graph
2. Topological sort
3. Circular dependency detection (cross-file)
4. Process files in correct order

### Phase 5: Code Generation (1-2 hours)

1. Update `generateEnhancedClass()` to use resolved parent info
2. Ensure generated imports are preserved
3. Test with multi-file scenarios

### Phase 6: Testing (2-3 hours)

1. Create test fixtures:
   - Two-file inheritance
   - Three-file chain
   - Multiple children from imported parent
   - Diamond pattern across files
2. Integration tests
3. Error case tests

**Total Estimated Time: 12-18 hours (1.5-2 days)**

## Edge Cases

### 1. Circular Dependencies Across Files

```zig
// file1.zig
const file2 = @import("file2.zig");
pub const A = zoop.class(struct {
    pub const extends = file2.B;
});

// file2.zig
const file1 = @import("file1.zig");
pub const B = zoop.class(struct {
    pub const extends = file1.A;  // ❌ Circular!
});
```

**Solution**: Detect during dependency graph construction, report error.

### 2. Deep Import Chains

```zig
// a.zig
pub const A = zoop.class(struct { ... });

// b.zig
const a = @import("a.zig");
pub const B = zoop.class(struct { pub const extends = a.A; });

// c.zig
const b = @import("b.zig");
pub const C = zoop.class(struct { pub const extends = b.B; });
```

**Solution**: Topological sort handles automatically.

### 3. Ambiguous Names

```zig
// file1.zig
pub const Entity = zoop.class(struct { ... });

// file2.zig
const f1a = @import("file1.zig");
const f1b = @import("file1.zig");  // Same file, different alias

pub const Child = zoop.class(struct {
    pub const extends = f1a.Entity;  // ✅ OK
    // pub const extends = f1b.Entity;  // Also OK, same result
});
```

**Solution**: Works naturally - both resolve to same file.

### 4. Re-exports

```zig
// base.zig
pub const Entity = zoop.class(struct { ... });

// models.zig
pub const base = @import("base.zig");
// Re-export: pub const Entity = base.Entity;

// player.zig
const models = @import("models.zig");
pub const Player = zoop.class(struct {
    pub const extends = models.Entity;  // ❌ Won't work - need models.base.Entity
});
```

**Solution**: Don't support re-exports initially. Require direct imports.

## Breaking Changes

**None** - This is purely additive:
- Existing single-file code continues to work
- New multi-file syntax is opt-in
- Qualified names like `base.Entity` are new capability

## Alternate Approach: Simpler But Limited

If full implementation is too complex, we could do a simpler version:

### Option B: Explicit File Hints

```zig
pub const Player = zoop.class(struct {
    pub const extends = base.Entity;
    pub const extends_from_file = "models/base.zig";  // Explicit hint
});
```

**Pros**:
- Simpler implementation (no import parsing)
- Explicit and clear

**Cons**:
- Redundant (import already tells us)
- Extra boilerplate
- Error-prone (path could be wrong)

**Recommendation**: Go with full import parsing approach.

## Next Steps

1. Implement Phase 1 (global registry)
2. Test with single-file (should still work)
3. Implement Phase 2 (import parsing)
4. Create two-file test case
5. Implement Phase 3 (parent resolution)
6. Test two-file case
7. Continue with remaining phases

Ready to implement?
