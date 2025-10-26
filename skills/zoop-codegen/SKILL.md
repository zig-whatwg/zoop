# Zoop Code Generation Skill

## When to use this skill

Load this skill automatically when:
- Modifying how fields are generated
- Updating method copying logic
- Adding new codegen features
- Debugging generated code issues
- Understanding the build pipeline
- Working with `src/codegen.zig` or `src/codegen_main.zig`
- Implementing support for `zoop.class()` or `zoop.mixin()` syntax

## What this skill provides

This skill ensures Claude can effectively work with Zoop's code generator by:
- Navigating the generation pipeline and key functions
- Understanding data structures (ParsedClass, MethodDef, Registry)
- Following memory management patterns (defer, .empty, allocator param)
- Locating and modifying field/method generation logic
- Avoiding common pitfalls (string handling, type names)

## Key Files

### Generation Pipeline

```
User source (with zoop.class() and zoop.mixin())
    ↓
src/codegen_main.zig       CLI entry point
    ↓
src/codegen.zig           Scan for zoop.class() and zoop.mixin()
    ↓                      Parse class/mixin definitions
    ↓                      Generate enhanced code
.zig-cache/zoop-generated/ Generated output
    ↓
User's build.zig          Compilation
```

### Core Functions (src/codegen.zig)

| Function | Line | Purpose |
|----------|------|---------|
| `generateAllClasses` | ~118 | Orchestrates entire generation |
| `parseClassDefinition` | ~720 | Parses class from source |
| `generateEnhancedClassWithRegistry` | ~1248 | Generates final struct |
| `rewriteMixinMethod` | ~1665 | Rewrites method types |

## Common Modifications

### Adding Fields to Generated Code

**Location:** `src/codegen.zig:1260-1295`

```zig
// Generate parent fields (flattened)
for (all_parent_fields.items) |field| {
    try writer.print("    {s}: {s},\n", .{ field.name, field.type_name });
}

// Generate mixin fields (flattened)
for (mixin_info.fields) |field| {
    try writer.print("    {s}: {s},\n", .{ field.name, field.type_name });
}

// Generate child fields
for (parsed.fields) |field| {
    try writer.print("    {s}: {s},\n", .{ field.name, field.type_name });
}
```

### Modifying Method Copying

**Location:** `src/codegen.zig:1390-1395`

```zig
for (parent_methods.items) |parent_method| {
    const method = parent_method.method;
    const parent_type = parent_method.parent_type;

    // Copy and rewrite parent method
    const rewritten_method = try rewriteMixinMethod(
        allocator, 
        method.source,  // Original source
        parent_type,    // From type
        parsed.name     // To type
    );
    defer allocator.free(rewritten_method);

    try writer.print("    {s}\n", .{rewritten_method});
}
```

### Type Rewriting Logic

**Location:** `src/codegen.zig:1665-1689`

The `rewriteMixinMethod` function:
1. Finds all occurrences of source type (e.g., `*Parent`)
2. Replaces with target type (e.g., `*Child`)
3. Handles both signatures and method bodies

## Data Structures

### ParsedClass
```zig
struct {
    name: []const u8,
    parent_name: ?[]const u8,
    mixin_names: [][]const u8,
    fields: []FieldDef,
    properties: []PropertyDef,
    methods: []MethodDef,
}
```

### MethodDef
```zig
struct {
    name: []const u8,
    signature: []const u8,
    return_type: []const u8,
    source: []const u8,     // Full source code
    is_static: bool,
}
```

### GlobalRegistry
```zig
HashMap(class_name → ClassInfo)
// Used for resolving parent and mixin references
```

## Build Commands

```bash
# Build codegen tool
zig build codegen

# Run codegen manually
./zig-out/bin/zoop-codegen \
    --source-dir src \
    --output-dir .zig-cache/zoop \
    --method-prefix "call_" \
    --getter-prefix "get_" \
    --setter-prefix "set_"
```

## Testing Changes

After modifying codegen:

1. **Rebuild:** `zig build`
2. **Run tests:** `zig build test`
3. **Check generated code:** Look at `.zig-cache/zoop-generated/`
4. **Verify examples:** Test with `test_consumer/`

## Common Pitfalls

### Memory Management
- Always use `defer allocator.free()` for allocated strings
- Use `.empty` for ArrayLists: `var list: ArrayList(T) = .empty;`
- Pass allocator to `append`: `try list.append(allocator, item);`

### String Handling
- Source positions are byte offsets, not char indices
- Use `std.mem.indexOfPos` for searching within strings
- Be careful with string slices (they reference original memory)

### Type Names
- Fully qualified names: `package.module.Type`
- Handle generic types: `ArrayList(u8)`
- Respect const/pointer modifiers: `*const Type` vs `*Type`

## Debugging Tips

### Enable Debug Output
```zig
// In src/codegen.zig, add:
std.debug.print("[DEBUG] Processing class: {s}\n", .{class_name});
```

### Check Generated Code
```bash
# Compare source vs generated
diff src/example.zig .zig-cache/zoop-generated/example.zig
```

### Trace Method Copying
Look for `[DEBUG] Rewriting method` output when `--verbose` flag is added.

## Extension Points

### Adding New Directives

To add `pub const implements = Interface`:

1. Parse in `parseClassDefinition` (~line 720)
2. Store in `ParsedClass` struct
3. Generate interface methods in `generateEnhancedClassWithRegistry`

### Custom Method Prefixes

Already supported via CLI:
```bash
--method-prefix "my_prefix_"
```

## Common Anti-Patterns to Avoid

### ❌ Assuming Methods Call Parent via `.super`

```zig
// ❌ WRONG (v0.1.0 approach - removed)
try writer.print("return self.super.{s}(", .{method.name});

// ✅ CORRECT (v0.2.0 approach - copy method)
const rewritten = try rewriteMixinMethod(allocator, method.source, parent_type, child_type);
try writer.print("{s}\n", .{rewritten});
```

### ❌ Forgetting `defer` for Allocations

```zig
// ❌ WRONG
const str = try allocator.dupe(u8, "text");
// Leaks if function returns early!

// ✅ CORRECT
const str = try allocator.dupe(u8, "text");
defer allocator.free(str);  // Always cleaned up
```

### ❌ Using `.init()` for ArrayList

```zig
// ❌ WRONG (Zig 0.15+)
var list = ArrayList(T).init(allocator);

// ✅ CORRECT
var list: ArrayList(T) = .empty;
defer list.deinit(allocator);
try list.append(allocator, item);  // Pass allocator!
```

## Quick Reference

**Pipeline**: codegen_main.zig → codegen.zig → .zig-cache/zoop-generated/

**Key Functions**:
- `generateAllClasses` (~118) - Orchestration
- `parseClassDefinition` (~720) - Parsing
- `generateEnhancedClassWithRegistry` (~1248) - Generation
- `rewriteMixinMethod` (~1665) - Type rewriting

**Memory**: Use `defer`, `.empty` for lists, pass allocator to `append`

**Strings**: Byte offsets, use `std.mem.indexOfPos`, slices reference original

**Testing**: Rebuild → `zig build test` → check `.zig-cache/zoop-generated/`

## References

- `src/codegen.zig` - Main implementation
- `src/codegen_main.zig` - CLI argument parsing
- `IMPLEMENTATION.md` - Architecture details
- Tests in `tests/` - Examples of generated code
