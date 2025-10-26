# Critical Security and Memory Safety Fixes

**Date**: 2025-10-26  
**Priority**: CRITICAL  
**Status**: Fixes identified, pending application

## Executive Summary

Deep code analysis revealed 3 critical security/memory issues in `src/codegen.zig` that require immediate fixes. These issues can cause memory leaks, DoS attacks, and potential code injection.

---

## Critical Issue #1: Memory Leaks in Error Paths

**Location**: `src/codegen.zig:800-850` (parseClassDefinition function)

**Problem**: After converting ArrayLists to owned slices with `toOwnedSlice()`, if subsequent operations fail, the owned slices are never freed because the `errdefer` blocks only handle the ArrayList state.

**Current Code Pattern (BUGGY)**:
```zig
var mixin_names: std.ArrayList([]const u8) = .empty;
errdefer {
    for (mixin_names.items) |mixin| allocator.free(mixin);
    mixin_names.deinit(allocator);
}
// ... populate mixin_names ...
return .{
    .mixin_names = try mixin_names.toOwnedSlice(allocator), // Line 842
    .fields = try fields.toOwnedSlice(allocator),            // Line 843
    .methods = try methods.toOwnedSlice(allocator),          // Line 844
    .properties = try properties.toOwnedSlice(allocator),    // Line 845
    // If error occurs here ↑, all 4 slices leak!
};
```

**Fix Required**:
```zig
var mixin_names = std.ArrayList([]const u8).init(allocator);
errdefer {
    for (mixin_names.items) |mixin| allocator.free(mixin);
    mixin_names.deinit();
}

var fields = std.ArrayList(FieldDef).init(allocator);
errdefer fields.deinit();

var methods = std.ArrayList(MethodDef).init(allocator);
errdefer methods.deinit();

var properties = std.ArrayList(PropertyDef).init(allocator);
errdefer properties.deinit();

try parseStructBody(allocator, class_body, &fields, &methods, &properties);

// Convert to owned slices with proper error handling
const mixin_names_slice = try mixin_names.toOwnedSlice();
errdefer {
    for (mixin_names_slice) |mixin| allocator.free(mixin);
    allocator.free(mixin_names_slice);
}

const fields_slice = try fields.toOwnedSlice();
errdefer allocator.free(fields_slice);

const methods_slice = try methods.toOwnedSlice();
errdefer allocator.free(methods_slice);

const properties_slice = try properties.toOwnedSlice();
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
```

**Impact**: Guaranteed memory leak when parsing fails after successful field/method/property parsing.

---

## Critical Issue #2: Unbounded Signature Scanning (DoS Vulnerability)

**Location**: `src/codegen.zig:888-927` (replaceFirstSelfType, extractParamNames)

**Problem**: Functions scan type signatures without length limits. An attacker can craft source files with extremely long or deeply nested type signatures to cause excessive CPU usage.

**Current Code (VULNERABLE)**:
```zig
fn replaceFirstSelfType(
    allocator: std.mem.Allocator,
    signature: []const u8,
    new_type: []const u8,
) ![]const u8 {
    if (signature.len < 2) return try allocator.dupe(u8, signature);
    // NO LENGTH CHECK - can be megabytes!
    const inner = signature[1 .. signature.len - 1];
    
    var type_end = type_start;
    while (type_end < inner.len) : (type_end += 1) { // Unbounded scan
        const c = inner[type_end];
        if (c == ',' or c == ')' or c == ' ') break;
    }
    // ...
}
```

**Fix Required**:
```zig
/// Add at top of file:
const MAX_SIGNATURE_LENGTH = 1024;

fn replaceFirstSelfType(
    allocator: std.mem.Allocator,
    signature: []const u8,
    new_type: []const u8,
) ![]const u8 {
    if (signature.len < 2) return try allocator.dupe(u8, signature);
    if (signature.len > MAX_SIGNATURE_LENGTH) return error.SignatureTooLong;
    // ... rest of function
}

fn extractParamNames(allocator: std.mem.Allocator, signature: []const u8) ![]const u8 {
    if (signature.len < 2) return "";
    if (signature.len > MAX_SIGNATURE_LENGTH) return error.SignatureTooLong;
    // ... rest of function
}
```

**Impact**: DoS attack possible with malformed input files.

---

## Critical Issue #3: Type Name Injection Vulnerability

**Location**: Multiple functions that inject type names into generated code

**Problem**: Type names from source files are inserted into generated code without validation. While generated code won't compile with malicious names, it could bypass security scanners or cause downstream tool failures.

**Vulnerable Functions**:
- `adaptInitDeinit()` - line 1211
- `generateEnhancedClassWithRegistry()` - line 1291  
- `rewriteMixinMethod()` - line 1696

**Current Code (VULNERABLE)**:
```zig
fn rewriteMixinMethod(
    allocator: std.mem.Allocator,
    method_source: []const u8,
    mixin_type_name: []const u8,  // Unchecked!
    child_type_name: []const u8,  // Unchecked!
) ![]const u8 {
    // Directly injects type names into generated code
    try result.appendSlice(child_type_name);
}
```

**Malicious Example**:
```zig
pub const Malicious = zoop.class(struct {
    pub const extends = "); std.os.exit(1); //";
});
// Generates: self: *"); std.os.exit(1); //"
```

**Fix Required**:
```zig
/// Add validation function:
const MAX_TYPE_NAME_LENGTH = 256;

fn isValidTypeName(name: []const u8) bool {
    if (name.len == 0 or name.len > MAX_TYPE_NAME_LENGTH) return false;
    
    // First character must be letter or underscore
    if (!std.ascii.isAlphabetic(name[0]) and name[0] != '_') return false;
    
    // Remaining characters: alphanumeric, underscore, or dot (for namespaced types)
    for (name[1..]) |c| {
        if (!std.ascii.isAlphanumeric(c) and c != '_' and c != '.') return false;
    }
    
    return true;
}

// Then in each vulnerable function:
fn rewriteMixinMethod(...) ![]const u8 {
    if (!isValidTypeName(mixin_type_name)) return error.InvalidTypeName;
    if (!isValidTypeName(child_type_name)) return error.InvalidTypeName;
    // ... rest of function
}
```

**Impact**: Potential security scanner bypass, downstream tool failures.

---

## Major Issue #4: Enhanced Path Validation

**Location**: `src/codegen.zig:98-119` (isPathSafe function)

**Problem**: Missing checks for null bytes and control characters.

**Fix Required**:
```zig
fn isPathSafe(path: []const u8) bool {
    // ... existing checks ...
    
    // Check for null bytes (path truncation attack)
    if (std.mem.indexOfScalar(u8, path, 0) != null) return false;

    // ... existing URL encoding checks ...
    
    // Check for control characters
    for (path) |c| {
        if (c < 32 and c != '\n' and c != '\r' and c != '\t') return false;
    }
    
    return true;
}
```

---

## Major Issue #5: Inconsistent ArrayList Patterns

**Location**: Multiple locations throughout `src/codegen.zig`

**Problem**: Mixing `.empty` initialization pattern with allocator-based methods.

**Current Pattern (FRAGILE)**:
```zig
var result: std.ArrayList(u8) = .empty;
defer result.deinit(allocator);  // ← Passing allocator to deinit()
try result.appendSlice(allocator, data);  // ← Passing allocator to appendSlice()
```

**Correct Pattern**:
```zig
var result = std.ArrayList(u8).init(allocator);
defer result.deinit();  // ← No allocator param
try result.appendSlice(data);  // ← No allocator param
```

**Locations to Fix**:
1. `filterZoopImport` - line 534
2. `processSourceFileWithRegistry` - line 597
3. `extractParamNames` - line 938
4. `adaptInitDeinit` - line 1217
5. `generateEnhancedClassWithRegistry` - line 1299
6. `rewriteMixinMethod` - line 1709
7. Several other locations with `.empty` pattern

---

## Required Error Types

Add these to the error set (or create GenerateError if it doesn't exist):

```zig
pub const GenerateError = error{
    // ... existing errors ...
    SignatureTooLong,
    InvalidTypeName,
    InvalidClassName,
} || std.mem.Allocator.Error || ...;
```

---

## Testing Recommendations

After fixes are applied:

1. **Memory Leak Test**: Create test that intentionally fails parsing after populating arrays
2. **DoS Test**: Test with 10KB+ type signature, verify it's rejected  
3. **Injection Test**: Test with malicious type names like `"); exit(1); //"`
4. **Path Security Test**: Test null bytes, control characters in paths

---

## Implementation Priority

1. **IMMEDIATE (Critical)**:
   - Fix #1: Memory leaks in parseClassDefinition
   - Fix #2: Signature length limits
   - Fix #3: Type name validation

2. **SHORT-TERM (Major)**:
   - Fix #4: Enhanced path validation
   - Fix #5: ArrayList pattern consistency

3. **VERIFICATION**:
   - Run existing tests: `zig build test`
   - Add new security tests
   - Run with leak detector: Memory tests pass

---

## Estimated Impact

**Before Fixes**:
- Memory leak: Guaranteed on specific error paths
- DoS risk: High with malformed input
- Injection risk: Low (won't compile but could bypass scanners)

**After Fixes**:
- Memory leak: Eliminated
- DoS risk: Mitigated (bounded processing)
- Injection risk: Eliminated (validated inputs)

**Code Quality Grade**:
- Before: B+ (good but with critical gaps)
- After: A- (production-ready for untrusted inputs)

---

## Notes

- All fixes maintain backward compatibility
- No API changes required
- Performance impact: Negligible (validation is O(n) on small strings)
- The codebase is otherwise well-written with good error handling patterns

---

## Author

Analysis and fix recommendations by Claude (Anthropic), 2025-10-26
