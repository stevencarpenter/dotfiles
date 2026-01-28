# AI Agent Tools & MCP Servers Reference

This document provides a comprehensive guide to all MCP servers and tools available to LLM agents in this environment. Use this to understand what capabilities are available and when to use each tool.

## Quick Reference

| Tool | Type | Best For | Status |
|------|------|----------|--------|
| **Serena** | MCP Server | Code understanding, semantic search, refactoring | ⚡ Always available in IDE |
| **GitHub** | MCP Server | Repository operations, PR management, issue handling | ✅ Configured globally |
| **Filesystem** | MCP Server | File reading, writing, organization | ✅ Core capability |
| **Railway** | MCP Server | Deployment status, logs, environment management | ✅ Project-specific |
| **Memory** | MCP Server | Session persistence, context retention | ✅ Configured |
| **Sequential Thinking** | MCP Server | Complex reasoning, multi-step analysis | ✅ Available |
| **Claude Code Plugins** | Tool System | IDE integration, code review, git operations | ⚡ Active in IDE |

---

## MCP Servers

### 1. **Serena** ⭐ PRIMARY CODE UNDERSTANDING

**Location**: `~/.local/share/chezmoi/scripts/serena-mcp`
**Mode**: Interactive, available in IDE (IntelliJ with Claude Code)
**Context**: `claude-code` (when used via Claude Code)

**Capabilities**:
- 🔍 Semantic code search across entire codebase
- 📍 Symbol resolution and navigation
- 🔗 Cross-reference finding
- 🏗️ Type hierarchy traversal
- 🧬 Code pattern analysis
- 📝 Docstring and documentation extraction

**When to Use**:
- ✅ Understanding architecture and code relationships
- ✅ Finding where functions are used
- ✅ Exploring type hierarchies
- ✅ Discovering patterns in the codebase
- ✅ Refactoring with full context
- ✅ Complex code analysis tasks

**When NOT to Use**:
- ❌ Simple regex pattern matching (use Grep/Glob)
- ❌ Reading a single file (use Read tool)
- ❌ Generic text search (use Grep)

**Example Usage**:
```
Need to: Find all places where `syncToLocations()` is called
Tool: Serena `find_referencing_symbols`
Result: Complete call graph with context
```

### 2. **GitHub** 📊 REPOSITORY & COLLABORATION

**Location**: Git repository at `stevencarpenter/dotfiles` (and others)
**Auth**: Requires `GITHUB_TOKEN`
**Capabilities**:
- 📝 Issue management (create, read, update, close)
- 🔀 Pull request operations (create, review, merge)
- 📋 Branch management
- 🔍 Code search across repos
- 💬 Issue and PR comments
- ✅ Status checks and deployment info

**When to Use**:
- ✅ Creating issues for bugs or features
- ✅ Managing pull requests
- ✅ Searching code across the organization
- ✅ Checking PR status and reviews
- ✅ Merging changes
- ✅ Tracking deployment history

**Example Usage**:
```
Need to: Create a PR for this feature branch
Tool: GitHub `create_pull_request`
Include: Title, description, base/head branches
```

### 3. **Filesystem** 📁 FILE OPERATIONS

**Capabilities**:
- 📖 Read files and directories
- ✍️ Write and edit files
- 📂 Directory creation and traversal
- 🔄 File organization and movement
- 🗑️ File deletion

**Permissions**: Limited to project directories + config files
**When to Use**:
- ✅ Reading configuration files
- ✅ Writing test data
- ✅ Organizing project files
- ✅ Creating new modules or utilities
- ✅ Backup or data manipulation

**When NOT to Use**:
- ❌ Code navigation (use Serena)
- ❌ Pattern search (use Grep)
- ❌ Semantic understanding (use Serena)

### 4. **Railway** 🚂 DEPLOYMENT & INFRASTRUCTURE

**Location**: Railway.app integration
**Auth**: Requires `RAILWAY_TOKEN`
**Capabilities**:
- 🚀 View deployment status
- 📊 Access build and deployment logs
- 🌍 Domain management
- 🔧 Environment variable configuration
- 📈 Service monitoring

**Projects Configured**:
- `clawdbot` - TypeScript bot deployment

**When to Use**:
- ✅ Checking deployment status
- ✅ Viewing build/deployment logs
- ✅ Managing environment configuration
- ✅ Troubleshooting failed deployments
- ✅ Domain and networking setup

**Example Usage**:
```
Need to: Check why the bot deployment failed
Tool: Railway `get-logs` with deployment ID
Result: Full build and deployment logs
```

### 5. **Memory (Claude Memory)** 🧠 SESSION PERSISTENCE

**Capabilities**:
- 💾 Store observations and findings
- 🔄 Retrieve previous session context
- 📚 Organize knowledge by topic
- 🔍 Search memory entries
- ⏱️ Timeline-based context retrieval

**When to Use**:
- ✅ After completing significant research
- ✅ Documenting architectural decisions
- ✅ Storing temporary findings
- ✅ Cross-session knowledge sharing
- ✅ Avoiding re-analysis of the same code

**Example Usage**:
```
After analyzing MCP sync script:
Tool: Memory `write_memory`
Name: "mcp_sync_architecture"
Content: Summary of findings and patterns
Later session: Retrieve to avoid re-reading 600 lines
```

### 6. **Sequential Thinking** 🤔 COMPLEX REASONING

**Capabilities**:
- 🧩 Multi-step problem decomposition
- 🔀 Branching analysis paths
- 📊 Trade-off evaluation
- 🎯 Goal-oriented reasoning
- ✓ Verification steps

**When to Use**:
- ✅ Complex architectural decisions
- ✅ Multi-option trade-off analysis
- ✅ Debugging subtle issues
- ✅ Performance optimization decisions
- ✅ Security review and analysis

**When NOT to Use**:
- ❌ Simple, straightforward tasks
- ❌ Already understood problems
- ❌ Time-sensitive changes

### 7. **Supabase** 🗄️ DATABASE & BACKEND (Project-Specific)

**Location**: Whistlepost project integration
**Auth**: Requires `SUPABASE_PROJECT_REF`, `SUPABASE_API_KEY`
**Capabilities**:
- 📊 Database schema inspection
- 🔍 Query building and testing
- 🔐 Row-level security management
- 📈 Realtime subscriptions
- 🔑 Authentication setup

**When to Use**:
- ✅ In Whistlepost project context
- ✅ Database schema exploration
- ✅ Query testing
- ✅ Authentication troubleshooting

---

## Claude Code Plugin Ecosystem

### Core Plugins (Version Controlled)

Located in `scripts/claude-enabled-plugins.json`, automatically synced to `~/.claude/settings.json`:

| Plugin | Purpose | When to Use |
|--------|---------|-------------|
| **context7** | API documentation | Researching library APIs and methods |
| **github** | Repository operations | PR/issue management, code search |
| **supabase** | Backend/database | Database schema, queries, auth |
| **greptile** | Code search | Finding code patterns across repos |
| **feature-dev** | Guided development | Complex feature implementation |
| **code-review** | PR analysis | Automated code review feedback |
| **commit-commands** | Git automation | Creating commits, pushing changes |
| **frontend-design** | UI/UX creation | Building frontend components |
| **security-guidance** | Security analysis | Vulnerability assessment |
| **playwright** | Browser automation | Web testing, UI interaction |
| **rust-analyzer-lsp** | Rust language server | Rust code analysis |
| **typescript-lsp** | TypeScript language server | TypeScript/JavaScript code |
| **pyright-lsp** | Python language server | Python code analysis |
| **ralph-wiggum** | Agentic coding | Autonomous code generation |
| **claude-mem** | Memory persistence | Cross-session context |
| **pr-review-toolkit** | Comprehensive PR review | Professional code review |
| **ralph-loop** | Loop agent automation | Iterative agent workflows |
| **lua-lsp** | Lua language server | Lua configuration files |

---

## Decision Trees: Which Tool to Use?

### I need to understand code

```
Is the code in the current project?
├─ YES, and I need semantic understanding
│  └─ Use: SERENA (find_referencing_symbols, find_symbol, type_hierarchy)
├─ YES, and I just need to read it
│  └─ Use: Read tool or Filesystem
└─ NO, searching across GitHub
   └─ Use: GITHUB (search_code)
```

### I need to manage repositories

```
Is it about GitHub operations?
├─ Creating/managing issues
│  └─ Use: GITHUB (issue_write, issue_read)
├─ Pull requests
│  └─ Use: GITHUB (create_pull_request) or COMMIT-COMMANDS plugin
├─ Code search
│  └─ Use: GITHUB (search_code) or GREPTILE plugin
└─ Deployment status
   └─ Use: RAILWAY (get-logs, list-deployments)
```

### I need to understand the architecture

```
Is this about code relationships?
├─ YES, complex multi-file architecture
│  ├─ Use: SERENA (jet_brains_find_referencing_symbols)
│  └─ Use: MEMORY (write findings for later)
├─ Simple pattern matching
│  └─ Use: Grep or Glob tools
└─ Need to reason about trade-offs
   └─ Use: SEQUENTIAL-THINKING
```

### I'm solving a complex problem

```
Does it require deep reasoning?
├─ YES, multi-step analysis
│  └─ Use: SEQUENTIAL-THINKING
├─ Multiple valid approaches exist
│  └─ Use: SEQUENTIAL-THINKING to compare
└─ Need to retain context across sessions
   └─ Use: MEMORY (save findings)
```

---

## Best Practices

### ✅ DO's

1. **Use Serena first** for code understanding
   - It's always available in IDE
   - Provides semantic context
   - Better than generic grep

2. **Store architectural decisions in Memory**
   - Write findings after major analysis
   - Avoid re-reading same code later
   - Cross-session knowledge transfer

3. **Use context-appropriate tools**
   - Don't use GitHub to read local files
   - Don't use Serena for simple regex
   - Match tool to task complexity

4. **Check tool availability**
   - Serena requires IDE + IntelliJ
   - GitHub requires GITHUB_TOKEN
   - Railway requires RAILWAY_TOKEN

5. **Use Claude Code plugins**
   - They're already configured
   - Designed for integrated IDE work
   - Better than manual tool invocation

### ❌ DON'Ts

1. **Don't use Serena for**
   - Simple string matching (use Grep)
   - Reading single files (use Read)
   - Generic pattern search (use Glob)

2. **Don't skip Memory**
   - After 30+ minutes of research
   - After understanding architecture
   - Before complex refactoring

3. **Don't ignore context limits**
   - Serena helps reduce token usage
   - Memory stores findings efficiently
   - Use them to stay within budget

4. **Don't use wrong authentication**
   - Check which tokens are required
   - Verify `GITHUB_TOKEN` is set
   - Check `.env` for API keys

---

## Configuration Files Reference

**Master MCP Config**: `dot_config/mcp/mcp-master.json`
- Single source of truth for servers
- Synced to all tools after `chezmoi apply`

**Claude Code Plugins**: `scripts/claude-enabled-plugins.json`
- Version-controlled plugin list
- Automatically merged on sync
- Manually add new discoveries

**Environment Variables**: `dot_config/zsh/encrypted_dot_env`
- Encrypted with age
- Contains: GITHUB_TOKEN, SUPABASE_PROJECT_REF, etc.
- Sourced at shell startup

---

## Troubleshooting

**Serena not available?**
- Check IntelliJ is connected to Claude Code
- Verify `--context=claude-code` in config
- Ensure `scripts/serena-mcp` exists

**GitHub operations failing?**
- Verify `GITHUB_TOKEN` is set
- Check token has required scopes
- Test with `gh auth status`

**Memory not persisting?**
- Use correct `memory_file_name`
- Check `.claude/` directory has write permissions
- Verify observations are being saved

**Tool results incomplete?**
- Check context window usage
- Use Memory to reduce token overhead
- Break large tasks into steps

---

## References

- **MCP Setup**: `docs/ai-tools/serena-mcp-setup.md`
- **Ralph/OpenCode**: `docs/ai-tools/ralph-opencode-setup.md`
- **Architecture**: `CLAUDE.md` project overview
- **Tests**: `tests/` for tool usage examples

