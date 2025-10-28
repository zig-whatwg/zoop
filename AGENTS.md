# Agent Skills for Zoop Development

This document explains how AI agents (like Claude) can use **Skills** to work more effectively with the Zoop codebase.

## What are Skills?

Skills are folders that contain instructions, scripts, and resources that help AI agents perform specific tasks. They work by:

- **Loading on-demand**: Only when relevant to the current task
- **Composable**: Multiple skills can work together
- **Portable**: Same format across all Claude products (Apps, Code, API)
- **Efficient**: Minimal context loading for speed

Learn more: [Anthropic's Skills announcement](https://www.anthropic.com/news/skills)

---

## Available Skills

### Critical Skills

#### 0. **pre-commit** (`skills/pre-commit/`) ⚠️ **MANDATORY**

**Purpose**: Ensure all code quality checks pass before every git commit

**When to use:**
- **ALWAYS** before running `git commit`
- User asks to commit changes
- Creating a pull request
- Preparing code for review

**Mandatory checks:**
1. ✅ `zig fmt --check src/ tests/` - Format check (NON-NEGOTIABLE)
2. ✅ `zig build` - Build check
3. ✅ `zig build test` - Test check
4. ✅ Regenerate code if needed (for code generator projects)

**Why this is critical:**
- CI enforces formatting - unformatted code WILL fail CI
- Prevents broken builds from being committed
- Catches regressions before they reach remote
- Maintains code quality standards

**Rule**: NEVER commit without running format check first.

---

### Directory Structure

All skills are located in the `skills/` directory:

```
zoop/
├── skills/
│   ├── pre-commit/            # Pre-commit checks (CRITICAL!)
│   ├── zig/                   # General Zig programming
│   ├── zoop-workflow/         # Developing with Zoop
│   ├── zoop-architecture/     # Understanding Zoop's design
│   ├── zoop-codegen/          # Working with code generation
│   ├── zoop-testing/          # Running and writing tests
│   └── zoop-documentation/    # Updating documentation
└── AGENTS.md                  # This file
```

### General Skills

#### 0. **zig** (`skills/zig/`)

**Purpose**: Write idiomatic, safe, and performant Zig code

**When to use:**
- Working with `.zig` files
- Writing or refactoring Zig code
- Designing struct layouts
- Managing memory with allocators
- Implementing error handling

**Key concepts:**
- Naming conventions (PascalCase types, snake_case functions)
- Memory management patterns (factory vs direct creation)
- Error handling with error unions
- Comptime programming
- Type safety best practices

**Resources:**
- `resources/advanced-patterns.md` - Advanced Zig patterns
- `resources/c-interop-reference.md` - C interop guide
- `resources/stdlib-reference.md` - Standard library reference
- `resources/templates/` - Project templates
- `scripts/new-project.sh` - Project scaffolding

---

### Zoop-Specific Skills

#### 1. **zoop-workflow** (`skills/zoop-workflow/`) ⭐ NEW

**Purpose**: Learn how to develop Zig libraries using Zoop's OOP code generation

**When to use:**
- Working on a project that uses Zoop
- Creating a new Zoop-based library
- Setting up zoop build integration
- Understanding the source vs generated file workflow

**Key concepts:**
- **NEVER edit generated files** (strict rule)
- Two-directory system (zoop_src/ for source, src/ for generated)
- Edit → Build → Test → Commit cycle
- Smart caching with descendant tracking
- Build system integration helpers
- Committing both source and generated files

**Resources:**
- `SKILL.md` - Complete workflow guide
- `examples/user-admin/` - Working User/Admin example
- `examples/build.zig` - Build configuration template

**Target audience**: Library authors using Zoop, AI assistants helping with Zoop projects

---

#### 2. **zoop-architecture** (`skills/zoop-architecture/`)

**Purpose**: Understand Zoop's flattened field inheritance architecture

**When to use:**
- Explaining how Zoop works
- Answering architectural questions
- Making design decisions

**Key concepts:**
- Flattened parent and mixin fields
- Method copying with type rewriting
- Zero-overhead design
- No `.super` field or `@ptrCast`

---

#### 2. **zoop-codegen** (`skills/zoop-codegen/`)

**Purpose**: Work with the code generator (`src/codegen.zig`)

**When to use:**
- Modifying field generation
- Updating method copying logic
- Adding new codegen features
- Debugging generated code

**Key files:**
- `src/codegen.zig` - Main generation logic
- `src/codegen_main.zig` - CLI entry point
- `src/class.zig` - Comptime stub

---

#### 3. **zoop-testing** (`skills/zoop-testing/`)

**Purpose**: Run tests and ensure nothing breaks

**When to use:**
- Verifying changes
- Adding new test cases
- Debugging test failures
- Performance testing

**Commands:**
```bash
zig build test              # Run all tests
zig build benchmark         # Run performance benchmarks
```

**Key test files:**
- `tests/test_mixins.zig` - Mixin functionality
- `tests/performance_test.zig` - Performance benchmarks
- `tests/memory_test.zig` - Memory safety

---

#### 4. **zoop-documentation** (`skills/zoop-documentation/`)

**Purpose**: Update documentation consistently

**When to use:**
- After architectural changes
- Adding new features
- Fixing documentation bugs
- Ensuring consistency

**Key files:**
- `README.md` - User-facing introduction
- `CONSUMER_USAGE.md` - Integration guide
- `API_REFERENCE.md` - API documentation
- `IMPLEMENTATION.md` - Architecture deep-dive

**Rules:**
- No `.super` references (fields are flattened)
- No `@ptrCast` references (methods are copied)
- Show direct field access: `dog.name` not `dog.super.name`
- Emphasize zero overhead

---

## Creating New Skills

To create a new skill for Zoop:

1. **Create directory**: `skills/your-skill-name/`
2. **Add SKILL.md**: Document the skill's purpose and usage
3. **Add resources**: Include example code, scripts, or data
4. **Test it**: Verify the skill loads and works correctly
5. **Update AGENTS.md**: Add documentation here

### Skill Template

```
skills/your-skill-name/
├── SKILL.md              # Skill documentation
├── examples/             # Example code or data
│   └── example.zig
└── resources/            # Additional resources
    └── reference.md
```

---

## Using Skills in Claude Code

Skills are automatically available in Claude Code when working with Zoop:

1. Clone the repository
2. Open in Claude Code
3. Skills load automatically when relevant
4. See them in Claude's chain of thought

Example:
```
User: "How does Zoop handle parent fields?"

Claude: [Loads zoop-architecture skill]
        Parent fields are flattened directly into child classes...
```

---

## Best Practices

### For Skill Developers

1. **Keep skills focused**: One skill = one domain
2. **Minimal context**: Only include essential files
3. **Clear documentation**: Explain when and how to use
4. **Versioned**: Update with codebase changes

### For AI Agents

1. **Load only when needed**: Don't load all skills at once
2. **Check skill date**: Skills may be outdated
3. **Verify with code**: Skills document intent, code is truth
4. **Ask for clarification**: When skills conflict with code

---

## Skill Maintenance

Skills should be updated when:

- Architecture changes (like v0.1.0 → v0.2.0 flattening)
- New features are added (like mixins)
- API changes
- Documentation standards change

### Update Checklist

- [ ] Update SKILL.md with new information
- [ ] Add/update examples
- [ ] Test the skill works correctly
- [ ] Update AGENTS.md if skill purpose changes

---

## Advanced: Skills for API Users

Developers using Zoop via API can create skills for their specific use cases:

```python
# Example: Custom skill for game engine development
skill = {
    "name": "zoop-game-entities",
    "description": "Generate game entity hierarchies with Zoop",
    "files": {
        "entity_template.zig": "...",
        "component_mixin.zig": "..."
    }
}
```

See [Anthropic's Skills documentation](https://docs.claude.com/en/docs/agents-and-tools/agent-skills/overview) for details.

---

## Resources

- [Anthropic Skills Announcement](https://www.anthropic.com/news/skills)
- [Skills Engineering Blog](https://www.anthropic.com/engineering/equipping-agents-for-the-real-world-with-agent-skills)
- [Skills Documentation](https://docs.claude.com/en/docs/agents-and-tools/agent-skills/overview)
- [Example Skills Repository](https://github.com/anthropics/skills)

---

## Contributing

To contribute a new skill:

1. Create the skill in `skills/`
2. Test it thoroughly
3. Document it in AGENTS.md
4. Submit a pull request

Skills help make Zoop development more efficient and accessible!
