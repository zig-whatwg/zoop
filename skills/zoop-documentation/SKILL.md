# Zoop Documentation Skill

## When to use this skill

Load this skill automatically when:
- After architectural changes
- When adding new features
- Fixing documentation bugs
- Ensuring terminology consistency
- Updating examples
- Working with any `.md` file in the project

## What this skill provides

This skill ensures Claude maintains documentation quality by:
- Enforcing critical rules (no `.super`, no `@ptrCast`)
- Following consistent terminology and style
- Using proper code block structure with ✅/❌ patterns
- Maintaining accuracy across all documentation files
- Avoiding outdated examples from v0.1.0

## Documentation Files

| File | Audience | Purpose |
|------|----------|---------|
| `README.md` | New users | Quick start, overview, features |
| `CONSUMER_USAGE.md` | Integrators | How to use Zoop in projects |
| `API_REFERENCE.md` | Developers | Detailed API documentation |
| `IMPLEMENTATION.md` | Contributors | Architecture deep-dive |
| `AGENTS.md` | AI agents | Skills and development patterns |
| `CHANGELOG.md` | Everyone | Version history |

## Critical Rules

### 1. NO `.super` References

**WRONG:**
```zig
dog.super.name
.super = Animal{ .name = "Max" }
self.super.eat()
```

**CORRECT:**
```zig
dog.name                    // Direct field access
.name = "Max", .age = 3     // Flattened initialization
self.name                   // Direct access in methods
```

**Why:** Fields are flattened in v0.2.0+

### 2. NO `@ptrCast` References

**WRONG:**
```zig
const parent_ptr: *Animal = @ptrCast(@alignCast(self));
// Methods use casting
```

**CORRECT:**
```zig
// Methods are copied with type rewriting
pub fn eat(self: *Dog) void {
    std.debug.print("{s} eating\n", .{self.name});
}
```

**Why:** Methods are copied, not delegated

### 3. Emphasize Zero Overhead

**Always mention:**
- Methods are copied (not delegated)
- No runtime casting
- No indirection
- Inline where applicable

## Common Documentation Tasks

### Adding a New Feature

1. **README.md**: Add to features list and quick example
2. **API_REFERENCE.md**: Document API in detail
3. **CONSUMER_USAGE.md**: Show usage example
4. **IMPLEMENTATION.md**: Explain how it works
5. **CHANGELOG.md**: Add to unreleased section

### Fixing Examples

**Check these patterns:**
```zig
// Initialization ✓
const dog = Dog{
    .name = "Max",        // Not .super = Animal{...}
    .age = 3,
    .breed = "Lab",
};

// Field access ✓
dog.name                   // Not dog.super.name

// Method calls ✓
dog.eat();                // Inherited method (copied)
dog.call_speak();         // Only if not overridden
```

### Updating After Architecture Changes

**Example:** When flattened fields were introduced

1. Search and replace: `\.super\.` → `.`
2. Update initialization examples
3. Rewrite field access examples
4. Update generated code examples
5. Fix method delegation descriptions
6. Update performance claims

## Style Guide

### Code Blocks

Use proper syntax highlighting:

```zig
const Dog = zoop.class(struct {
    pub const extends = Animal;
    breed: []const u8,
});
```

### Terminology

| Use | Don't Use |
|-----|-----------|
| "flattened" | "embedded" (for fields) |
| "copied" | "delegated" (for methods) |
| "type rewriting" | "casting" |
| "zero overhead" | "minimal overhead" |
| "direct access" | "access via super" |

### Example Structure

```markdown
## Feature Name

Brief description.

**Source:**
```zig
// Your code
```

**Generated:**
```zig
// What Zoop produces
```

**Usage:**
```zig
// How to use it
```

**Benefits:**
- Benefit 1
- Benefit 2
```

## Documentation Checklist

When updating docs:

- [ ] Terminology is consistent
- [ ] No `.super` references
- [ ] No `@ptrCast` references  
- [ ] Code examples compile
- [ ] Examples show current architecture
- [ ] Performance claims are accurate
- [ ] Links work
- [ ] Grammar/spelling checked

## File-Specific Guidelines

### README.md

**Focus:** Quick start and "wow factor"
**Tone:** Enthusiastic but accurate
**Length:** Keep examples short (<20 lines)
**Structure:** 
- Hero section
- Features
- Quick start
- Core concepts
- Advanced usage

### CONSUMER_USAGE.md

**Focus:** Complete integration guide
**Tone:** Tutorial-style, step-by-step
**Length:** Detailed (longer examples OK)
**Structure:**
- Installation
- Patterns
- Writing classes
- Configuration
- Troubleshooting

### API_REFERENCE.md

**Focus:** Complete API coverage
**Tone:** Technical, precise
**Length:** Comprehensive
**Structure:**
- Build API
- Class API
- CLI tool
- Error messages

### IMPLEMENTATION.md

**Focus:** How Zoop works internally
**Tone:** Technical, educational
**Length:** Detailed with code snippets
**Structure:**
- Architecture
- Parser
- Generator
- Edge cases
- Performance

## Common Mistakes

### 1. Mixing v0.1.0 and v0.2.0 Syntax

**Wrong:**
```zig
// v0.1.0 style (embedded)
const dog = Dog{
    .super = Animal{ .name = "Max" },
    .breed = "Lab",
};
```

**Right:**
```zig
// v0.2.0 style (flattened)
const dog = Dog{
    .name = "Max",
    .breed = "Lab",
};
```

### 2. Incorrect Performance Claims

**Wrong:** "Methods use inline delegation for minimal overhead"
**Right:** "Methods are copied for zero overhead"

### 3. Outdated Examples

Always test examples:
```bash
# Extract example to file
cat > test_example.zig << 'EOF'
// Example code here
EOF

# Test it compiles
zig build-exe test_example.zig
```

## Tools

### Search and Replace Patterns

```bash
# Find .super references
grep -r "\.super" --include="*.md" .

# Find @ptrCast references
grep -r "@ptrCast" --include="*.md" .

# Find outdated terminology
grep -r "embedded parent" --include="*.md" .
```

### Link Validation

```bash
# Check for broken links (markdown-link-check)
npx markdown-link-check README.md
```

## Version History

### v0.1.0 → v0.2.0 Changes

**Architecture:** Embedded → Flattened
**Key changes:**
- `.super` field removed
- `@ptrCast` delegation removed
- Method copying added
- Direct field access

**Documentation impact:**
- All examples rewritten
- Core concepts section overhauled
- Performance claims updated

## Quick Reference

**Critical Rules**:
- NO `.super` field access (fields are flattened)
- NO `@ptrCast` references (methods are copied)
- Always use ✅/❌ for correct/incorrect examples

**Terminology**:
- "flattened" (not "embedded") for fields
- "copied" (not "delegated") for methods
- "zero overhead" (not "minimal overhead")

**File Purposes**:
- `README.md` - Quick start, features
- `CONSUMER_USAGE.md` - Integration guide
- `API_REFERENCE.md` - Complete API
- `IMPLEMENTATION.md` - Architecture details

**Search Commands**:
```bash
grep -r "\.super" --include="*.md" .
grep -r "@ptrCast" --include="*.md" .
```

**Update Checklist**:
- [ ] No `.super` references
- [ ] No `@ptrCast` references
- [ ] Terminology consistent
- [ ] Examples compile
- [ ] Links work

## References

- `README.md` - User-facing docs
- `CONSUMER_USAGE.md` - Integration guide
- `API_REFERENCE.md` - API details
- `IMPLEMENTATION.md` - Architecture
- Commits `73a95e2`, `3496872` - Doc updates for v0.2.0
