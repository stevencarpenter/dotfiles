# AI Agent Tools & MCP Servers Reference

This document provides a comprehensive guide to all MCP servers and tools available to LLM agents in this environment. Use this to understand what capabilities are available and when to use each tool.

## Quick Reference

| Tool | Type | Best For | Status |
|------|------|----------|--------|
| **GitHub** | MCP Server | Repository operations, PR management, issue handling | ✅ Configured globally |
| **Filesystem** | MCP Server | File reading, writing, organization | ✅ Core capability |
| **Railway** | MCP Server | Deployment status, logs, environment management | ✅ Project-specific |
| **Memory** | MCP Server | Session persistence, context retention | ✅ Configured |
| **Sequential Thinking** | MCP Server | Complex reasoning, multi-step analysis | ✅ Available |
| **Claude Code Plugins** | Tool System | IDE integration, code review, git operations | ⚡ Active in IDE |

---

## MCP Servers

### 1. **GitHub** 📊 REPOSITORY & COLLABORATION

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

### 2. **Railway** 🚂 DEPLOYMENT & INFRASTRUCTURE

**Location**: Railway.app integration
**Auth**: Requires `RAILWAY_TOKEN`
**Capabilities**:
- 🚀 View deployment status
- 📊 Access build and deployment logs
- 🌍 Domain management
- 🔧 Environment variable configuration
- 📈 Service monitoring

**Projects Configured**:

- `whistlepost` - Rust monolith for train enthusiasts

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

### I need to understand code

```
Is the code in the current project?
├─ YES, and I need semantic understanding
│  └─ Use: Grep, Glob, or finder tools
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
│  ├─ Use: Grep, Glob, or finder tools
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

1. **Use appropriate search tools** for code understanding
   - Grep for exact matches
   - Glob for file patterns
   - finder for semantic searches

2. **Store architectural decisions in Memory**
   - Write findings after major analysis
   - Avoid re-reading same code later
   - Cross-session knowledge transfer

3. **Use context-appropriate tools**
   - Don't use GitHub to read local files
   - Match tool to task complexity

4. **Check tool availability**
   - GitHub requires GITHUB_TOKEN
   - Railway requires RAILWAY_TOKEN

5. **Use Claude Code plugins**
   - They're already configured
   - Designed for integrated IDE work
   - Better than manual tool invocation

6. **Start tasks with uv**
   - `uv run --project ~/.local/share/chezmoi/mcp_sync sync-mcp-configs` keeps MCP servers in sync across tools
   - `uv run ruff check scripts tests` enforces consistent formatting and lint rules
   - `uv run pytest tests/ -v` verifies the sync logic before deployment

### ❌ DON'Ts

1. **Don't use wrong tool for the job**
   - Simple string matching → use Grep
   - Reading single files → use Read
   - Generic pattern search → use Glob

2. **Don't skip Memory**
   - After 30+ minutes of research
   - After understanding architecture
   - Before complex refactoring

3. **Don't ignore context limits**
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

**Claude Code Plugins**: `dot_config/mcp/overrides/claude.json`
- Version-controlled plugin list
- Automatically merged on sync
- Manually add new discoveries

**Environment Variables**: `dot_config/zsh/encrypted_dot_env`
- Encrypted with age
- Contains: GITHUB_TOKEN, SUPABASE_PROJECT_REF, etc.
- Sourced at shell startup

---

## Troubleshooting

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

- **MCP Setup**: `docs/ai-tools/`
- **Ralph/OpenCode**: `docs/ai-tools/ralph-opencode-setup.md`
- **Architecture**: `CLAUDE.md` project overview
- **Tests**: `tests/` for tool usage examples
