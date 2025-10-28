# Pre-Commit Checks Skill

## Purpose

**CRITICAL**: Ensure all code quality checks pass before every single git commit.

This skill prevents CI failures by catching issues locally before pushing to remote.

---

## When to Use This Skill

**ALWAYS** load this skill when:
- About to run `git commit`
- User asks to commit changes
- Creating a pull request
- Preparing code for review

---

## Pre-Commit Checklist

Before EVERY commit, you MUST complete ALL of these checks:

### ✅ 1. Format Check (MANDATORY)

```bash
# Check if all files are properly formatted
zig fmt --check src/ tests/

# If files need formatting, format them:
zig fmt src/ tests/

# Stage the formatted files
git add src/ tests/
```

**Rule**: NEVER commit without running `zig fmt --check` first.

**Why**: The CI pipeline enforces formatting. Unformatted code will fail CI.

---

### ✅ 2. Build Check

```bash
# Ensure the project builds without errors
zig build

# For code generator projects
zig build codegen
```

**Rule**: Code must compile before committing.

**Why**: Broken code breaks everyone's workflow.

---

### ✅ 3. Test Suite

```bash
# Run all tests
zig build test

# Check test output for failures
```

**Rule**: All tests must pass before committing.

**Why**: Tests catch regressions and ensure correctness.

---

### ✅ 4. Regenerate Code (If Applicable)

For projects using code generation (like Zoop):

```bash
# Clear cache if needed
rm -rf .zig-cache/zoop-manifest.json

# Regenerate all code
./zig-out/bin/zoop-codegen --source-dir zoop_src --output-dir src

# Stage generated files
git add src/
```

**Rule**: Always commit both source and generated files together.

**Why**: Keeps source and generated code in sync.

---

## Pre-Commit Workflow

### Standard Commit Flow

```bash
# 1. Format check (MANDATORY)
zig fmt --check src/ tests/
# If needed: zig fmt src/ tests/ && git add src/ tests/

# 2. Build check
zig build

# 3. Test check
zig build test

# 4. Stage changes
git add <files>

# 5. Commit
git commit -m "Your message"

# 6. Push
git push origin <branch>
```

### Quick One-Liner

```bash
zig fmt --check src/ tests/ && zig build test && git commit -m "message"
```

---

## Common Failures and Fixes

### ❌ Format Check Failed

**Error**:
```
tests/codegen_bugs_test/actual/bug2_function_truncation.zig
```

**Fix**:
```bash
# Format the files
zig fmt tests/codegen_bugs_test/actual/*.zig

# Stage them
git add tests/codegen_bugs_test/actual/

# Check again
zig fmt --check src/ tests/
```

---

### ❌ Build Failed

**Error**:
```
error: duplicate struct member name 'allocator'
```

**Fix**:
1. Fix the compilation error in source
2. Run `zig build` to verify
3. Re-run format check
4. Commit

---

### ❌ Test Failed

**Error**:
```
Test [5/10] test.memory_leak... FAILED
```

**Fix**:
1. Run specific test: `zig test tests/memory_test.zig`
2. Debug and fix the issue
3. Run full test suite: `zig build test`
4. Commit when all pass

---

## CI Pipeline Checks

The CI pipeline runs these checks automatically. Running them locally saves time:

```yaml
# From .github/workflows/ci.yml
- name: Check formatting
  run: zig fmt --check src/ tests/

- name: Build
  run: zig build

- name: Run tests
  run: zig build test
```

**Pro Tip**: Run the exact same commands locally to match CI environment.

---

## Integration with Git Hooks (Optional)

You can automate these checks with a git pre-commit hook:

```bash
#!/bin/bash
# .git/hooks/pre-commit

echo "Running pre-commit checks..."

# Format check
if ! zig fmt --check src/ tests/ >/dev/null 2>&1; then
    echo "❌ Format check failed. Running formatter..."
    zig fmt src/ tests/
    git add src/ tests/
    echo "✅ Files formatted and staged"
fi

# Build check
if ! zig build >/dev/null 2>&1; then
    echo "❌ Build failed. Fix errors before committing."
    exit 1
fi

# Test check
if ! zig build test >/dev/null 2>&1; then
    echo "❌ Tests failed. Fix tests before committing."
    exit 1
fi

echo "✅ All pre-commit checks passed!"
```

Make it executable:
```bash
chmod +x .git/hooks/pre-commit
```

---

## Agent Workflow

When an AI agent (like Claude) is asked to commit code, follow this workflow:

```
1. Review changes: git status, git diff
2. Format check: zig fmt --check src/ tests/
3. Auto-format if needed: zig fmt src/ tests/ && git add src/ tests/
4. Build check: zig build
5. Test check: zig build test
6. Stage files: git add <relevant files>
7. Write commit message (analyze changes)
8. Commit: git commit -m "message"
9. Tag if releasing: git tag -a vX.Y.Z -m "Release X.Y.Z"
10. Push: git push origin <branch> [--tags]
```

**Rule**: NEVER skip step 2 (format check). It's mandatory.

---

## Quick Reference

| Check | Command | Why |
|-------|---------|-----|
| **Format** | `zig fmt --check src/ tests/` | CI enforces formatting |
| **Build** | `zig build` | Code must compile |
| **Test** | `zig build test` | Catch regressions |
| **Codegen** | `./zig-out/bin/zoop-codegen ...` | Keep generated code in sync |

---

## Emergency Override (NEVER USE)

If you absolutely MUST commit without checks (e.g., emergency hotfix):

```bash
git commit --no-verify -m "EMERGENCY: reason"
```

**WARNING**: This bypasses all safety checks. Use with extreme caution.

**Better approach**: Fix the issue properly and run checks.

---

## Summary

**ALWAYS** before committing:

1. ✅ Run `zig fmt --check src/ tests/`
2. ✅ Run `zig build`
3. ✅ Run `zig build test`
4. ✅ Stage and commit

**NEVER** commit without running format check first. This is non-negotiable.

Following this workflow prevents CI failures and maintains code quality.
