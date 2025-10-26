# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 1.0.x   | :white_check_mark: |
| < 1.0   | :x:                |

---

## Threat Model

### Assumed Trust Boundaries

Zoop operates with the following security assumptions:

#### **Untrusted Inputs** ❌
- Source `.zig` files containing `zoop.class()` declarations
- File paths provided to the code generator
- Class names, parent references, and mixin declarations
- Method signatures and type names

#### **Trusted Inputs** ✅
- The Zoop library code itself
- The Zig compiler and standard library
- The build system configuration
- Command-line arguments to `zoop-codegen` (from build scripts)

### Attack Surface

Zoop's primary attack surface is the **code generator** (`zoop-codegen`), which:
1. Reads arbitrary `.zig` source files
2. Parses class definitions
3. Generates new `.zig` code files
4. Writes to the filesystem

**Potential attacks**:
- Path traversal to read/write outside intended directories
- Code injection via malicious type names
- DoS via extremely large or complex inputs
- Memory exhaustion through unbounded allocations

---

## Security Features

### 1. Path Traversal Protection

**Implementation**: `isPathSafe()` in `src/codegen.zig`

**Protections**:
- ✅ Blocks parent directory references (`..`)
- ✅ Blocks absolute paths (`/`, `C:`)
- ✅ Blocks Windows path separators (`\`)
- ✅ Blocks null bytes (`\x00`)
- ✅ Blocks URL-encoded traversal (`%2e`, `%252e`)
- ✅ Blocks control characters (SOH, BEL, ESC, etc.)

**Example blocked paths**:
```
../../../etc/passwd
C:\Windows\System32
src%2e%2e/sensitive
src/\x00hidden.zig
```

**Testing**: See `tests/security_test.zig` for comprehensive path validation tests.

---

### 2. Type Name Injection Prevention

**Implementation**: `isValidTypeName()` in `src/codegen.zig`

**Protections**:
- ✅ Validates identifiers follow Zig syntax rules
- ✅ Only allows alphanumeric, underscore, and dot
- ✅ Rejects code injection attempts
- ✅ Length limit of 256 characters

**Example blocked type names**:
```zig
"); std.os.exit(1); //
Type'; DROP TABLE users;--
Type\nconst malicious = true;
MyVeryLongTypeNameThatExceeds256Characters...
```

**Context-aware replacement** (`rewriteMixinMethod()`):
- Doesn't replace type names inside string literals
- Doesn't replace type names inside comments
- Only replaces complete identifier matches

---

### 3. DoS Protection

**Resource Limits**:

| Resource | Limit | Constant | Rationale |
|----------|-------|----------|-----------|
| File Size | 5 MB | `MAX_FILE_SIZE` | Prevents memory exhaustion |
| Inheritance Depth | 256 levels | `MAX_INHERITANCE_DEPTH` | Prevents stack overflow |
| Type Signature | 1024 chars | `MAX_SIGNATURE_LENGTH` | Prevents unbounded parsing |
| Type Name | 256 chars | `MAX_TYPE_NAME_LENGTH` | Reasonable identifier limit |

**Bounded Operations**:
- ✅ All string scanning has maximum lengths
- ✅ Circular inheritance detected and rejected
- ✅ File I/O operations have size limits
- ✅ No recursive algorithms with unbounded depth

---

### 4. Memory Safety

**Allocator Management**:
- ✅ All allocations use `std.mem.Allocator`
- ✅ Proper `defer` and `errdefer` cleanup
- ✅ Memory leak detection in CLI (`GeneralPurposeAllocator`)
- ✅ No unsafe pointer casts (`@ptrCast`, `@alignCast`)

**Error Path Safety**:
- ✅ `errdefer` blocks for owned slices
- ✅ Proper cleanup on parse failures
- ✅ Validated with `std.testing.allocator`

**Testing**: See `tests/memory_test.zig` for comprehensive memory safety tests.

---

### 5. Thread Safety

**Status**: ⚠️ NOT THREAD-SAFE

The code generator (`generateAllClasses()`) is designed for single-threaded execution:
- `GlobalRegistry` uses non-atomic HashMap operations
- File I/O shares mutable state
- `ArrayListUnmanaged` not safe for concurrent access

**Mitigation**: Always call from a single thread. See thread safety documentation in `src/codegen.zig`.

---

## Security Testing

### Test Coverage

Comprehensive security tests in `tests/security_test.zig`:

| Category | Tests |
|----------|-------|
| Path validation | 6 tests |
| Type name validation | 5 tests |
| Injection prevention | 3 tests |
| Resource limits | 3 tests |

**Run security tests**:
```bash
zig build test
```

### Recommended Testing

For production use, consider:

1. **Fuzz Testing**: Test with randomized/malformed inputs
2. **Integration Testing**: Test with untrusted source repositories
3. **Resource Exhaustion**: Test with maximum-size inputs
4. **Unicode Edge Cases**: Test with various Unicode characters

---

## Known Limitations

### 1. Integer Overflow (Extreme Edge Case)

**Status**: ✅ **FIXED** in v1.0

Previously, calculating total field count could theoretically overflow with:
- 1000+ parent class fields
- 1000+ mixin fields  
- 1000+ child fields

**Mitigation**: Added overflow checking with `@addWithOverflow` in `src/class.zig:297`.

### 2. Comptime vs Runtime

**Validation scope**:
- ✅ Runtime generation (string-based): Fully validated
- ⚠️ Comptime stubs (`src/class.zig`): Trusted input assumed

Comptime code uses Zig's type system, which provides inherent safety but doesn't validate external input the same way runtime code does.

---

## Reporting Security Issues

### Responsible Disclosure

**DO NOT** open public GitHub issues for security vulnerabilities.

**Instead**:

1. **Email**: security@example.com (replace with actual contact)
2. **Subject**: `[SECURITY] Zoop - <brief description>`
3. **Include**:
   - Description of the vulnerability
   - Steps to reproduce
   - Potential impact
   - Suggested fix (if any)

### Response Timeline

| Action | Timeline |
|--------|----------|
| Initial Response | 48 hours |
| Triage & Assessment | 7 days |
| Fix Development | 14 days |
| Public Disclosure | 30 days after fix |

### Bug Bounty

Currently, Zoop does not offer a bug bounty program. Contributors will be credited in:
- `CHANGELOG.md`
- GitHub release notes
- This security policy

---

## Security Changelog

### v1.0.0 (2025-10-26)

**Added**:
- ✅ Path traversal protection (`isPathSafe`)
- ✅ Type name injection prevention (`isValidTypeName`)
- ✅ Signature length limits (`MAX_SIGNATURE_LENGTH`)
- ✅ Comprehensive security test suite
- ✅ Context-aware type replacement
- ✅ Integer overflow protection
- ✅ Memory leak prevention in error paths

**Validated**:
- All 60 tests pass including 17 security-specific tests
- Memory leak detection active in CLI
- No unsafe operations (`@ptrCast`, etc.)

---

## Best Practices for Users

### 1. Validate Source Files

Before processing source files from untrusted sources:

```bash
# Check file sizes
find src/ -name "*.zig" -size +5M

# Check for suspicious patterns
rg -i "\\x00|%2e|\.\./" src/

# Validate encoding
file -i src/*.zig
```

### 2. Sandbox Code Generation

Run code generation in an isolated environment:

```bash
# Use a separate user account
sudo -u codegen-user zoop-codegen --source-dir src --output-dir out

# Or use containers
docker run --rm -v ./src:/src:ro -v ./out:/out:rw zoop-codegen
```

### 3. Review Generated Code

Always review generated code before committing:

```bash
# Diff generated vs previous
git diff --cached generated/

# Look for suspicious patterns
rg -i "exit|exec|system|os\.|std\.process" generated/
```

### 4. Limit Resource Usage

Set resource limits when running code generation:

```bash
# Limit memory (Linux)
ulimit -m 512000  # 512MB

# Timeout
timeout 60s zoop-codegen --source-dir src --output-dir out
```

---

## Compliance

### Zig Language Security

Zoop follows Zig language security best practices:
- No undefined behavior in safe code paths
- Memory safety through allocator tracking
- Compile-time validation where possible
- Clear error propagation

### OWASP Guidelines

Relevant OWASP protections:
- **A01: Broken Access Control**: Path traversal protection
- **A03: Injection**: Type name validation
- **A04: Insecure Design**: Secure-by-default configuration
- **A05: Security Misconfiguration**: Clear security documentation

---

## License

This security policy is part of the Zoop project and follows the same license as the main project (see LICENSE file).

---

## Acknowledgments

### Security Contributors

- Initial security analysis and fixes: Anthropic Claude (2025-10-26)

### Security Tools

- Zig `GeneralPurposeAllocator` for leak detection
- `std.testing.allocator` for memory safety tests
- Static analysis via Zig compiler

---

**Last Updated**: 2025-10-26  
**Version**: 1.0.0  
**Status**: Active Maintenance
