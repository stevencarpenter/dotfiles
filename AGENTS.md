# Repository Guidelines

## Project Structure & Module Organization

This repository is a chezmoi-managed dotfiles source. Top-level `dot_*` and `dot_config/...` paths map to files under `$HOME` when applied.

- `dot_config/`: primary tool configs (zsh, nvim, tmux, mise, mcp, dev-container, yazi).
- `.chezmoiscripts/`: automation hooks run during apply/update.
- `mcp_sync/`: Python package for MCP config synchronization (`src/mcp_sync`, `tests/`).
- `docs/` and `arch/`: setup guides and platform scripts.

## Build, Test, and Development Commands

Use these commands from repo root unless noted:

- `chezmoi diff`: preview changes before applying.
- `chezmoi apply -v`: apply dotfiles and run sync hooks.
- `uv run --project ~/.local/share/chezmoi/mcp_sync sync-mcp-configs`: manual MCP sync.
- `cd mcp_sync && uv run pytest -v`: run Python tests.
- `cd mcp_sync && uv run ruff check src tests`: lint Python code.
- `pre-commit run --all-files`: run repo-wide YAML/TOML/JSON and hygiene checks.

## Coding Style & Naming Conventions

- Python: 4-space indentation, `snake_case` for modules/functions, `PascalCase` for classes.
- Python docstrings: use verbose Google-style docstrings for classes/functions with typed `Args:` and `Returns:` sections; include `Raises:` when relevant.
- Tests: `test_*.py` filenames and `test_*` function names (enforced by pre-commit).
- Chezmoi source naming: keep `dot_` prefixes for managed dotfiles and `encrypted_` for age-encrypted sources.
- Prefer small, focused edits; keep scripts idempotent and safe to re-run.

## Testing Guidelines

- Primary framework: `pytest` (see `mcp_sync/tests/`).
- Add/adjust tests for behavior changes in sync logic, template rendering, or CLI flags.
- Run `uv run pytest -v` before opening a PR; use `-k <pattern>` for targeted checks while iterating.

## Commit & Pull Request Guidelines

History favors Conventional Commit-style prefixes: `feat:`, `fix:`, `chore:`, `docs:`.

- Commit format: `type: short imperative summary` (optionally include PR/issue like `(#12)`).
- Keep commits scoped to one concern.
- PRs should include: purpose, key changed paths, test/lint evidence, and any config/security impact (especially secrets, MCP, or shell startup behavior).
- Include screenshots only when UI/docs rendering changes require visual confirmation.

## Skills

A skill is a set of local instructions to follow that is stored in a `SKILL.md` file. Below is the list of skills that can be used. Each entry includes a name,
description, and file path so you can open the source for full instructions when using a specific skill.

### Available skills

- brainstorming: You MUST use this before any creative work - creating features, building components, adding functionality, or modifying behavior. Explores user
  intent, requirements and design before implementation. (file: `$CODEX_HOME/superpowers/skills/brainstorming/SKILL.md`)
- cloudflare-deploy: Deploy applications and infrastructure to Cloudflare using Workers, Pages, and related platform services. Use when the user asks to deploy,
  host, publish, or set up a project on Cloudflare. (file: `$CODEX_HOME/skills/cloudflare-deploy/SKILL.md`)
- dev-browser: Browser automation with persistent page state. Use when users ask to navigate websites, fill forms, take screenshots, extract web data, test web
  apps, or automate browser workflows. Trigger phrases include "go to [url]", "click on", "fill out the form", "take a screenshot", "scrape", "automate", "test
  the website", "log into", or any browser interaction request. (file: `$CODEX_HOME/skills/dev-browser/SKILL.md`)
- dispatching-parallel-agents: Use when facing 2+ independent tasks that can be worked on without shared state or sequential dependencies (file:
  `$CODEX_HOME/superpowers/skills/dispatching-parallel-agents/SKILL.md`)
- executing-plans: Use when you have a written implementation plan to execute in a separate session with review checkpoints (file:
  `$CODEX_HOME/superpowers/skills/executing-plans/SKILL.md`)
- finishing-a-development-branch: Use when implementation is complete, all tests pass, and you need to decide how to integrate the work - guides completion of
  development work by presenting structured options for merge, PR, or cleanup (file:
  `$CODEX_HOME/superpowers/skills/finishing-a-development-branch/SKILL.md`)
- gh-address-comments: Help address review/issue comments on the open GitHub PR for the current branch using gh CLI; verify gh auth first and prompt the user to
  authenticate if not logged in. (file: `$CODEX_HOME/skills/gh-address-comments/SKILL.md`)
- gh-fix-ci: Inspect GitHub PR checks with gh, pull failing GitHub Actions logs, summarize failure context, then create a fix plan and implement after user
  approval. Use when a user asks to debug or fix failing PR CI/CD checks on GitHub Actions and wants a plan + code changes; for external checks (e.g.,
  Buildkite), only report the details URL and mark them out of scope. (file: `$CODEX_HOME/skills/gh-fix-ci/SKILL.md`)
- notion-knowledge-capture: Capture conversations and decisions into structured Notion pages; use when turning chats/notes into wiki entries, how-tos,
  decisions, or FAQs with proper linking. (file: `/Users/scarpenter/.codex/skills/notion-knowledge-capture/SKILL.md`)
- notion-meeting-intelligence: Prepare meeting materials with Notion context and Codex research; use when gathering context, drafting agendas/pre-reads, and
  tailoring materials to attendees. (file: `/Users/scarpenter/.codex/skills/notion-meeting-intelligence/SKILL.md`)
- notion-research-documentation: Research across Notion and synthesize into structured documentation; use when gathering info from multiple Notion sources to
  produce briefs, comparisons, or reports with citations. (file: `/Users/scarpenter/.codex/skills/notion-research-documentation/SKILL.md`)
- notion-spec-to-implementation: Turn Notion specs into implementation plans, tasks, and progress tracking; use when implementing PRDs/feature specs and
  creating Notion plans + tasks from them. (file: `/Users/scarpenter/.codex/skills/notion-spec-to-implementation/SKILL.md`)
- openai-docs: Use when the user asks how to build with OpenAI products or APIs and needs up-to-date official documentation with citations (for example: Codex,
  Responses API, Chat Completions, Apps SDK, Agents SDK, Realtime, model capabilities or limits); prioritize OpenAI docs MCP tools and restrict any fallback
  browsing to official OpenAI domains. (file: `/Users/scarpenter/.codex/skills/openai-docs/SKILL.md`)
- playwright: Use when the task requires automating a real browser from the terminal (navigation, form filling, snapshots, screenshots, data extraction, UI-flow
  debugging) via `playwright-cli` or the bundled wrapper script. (file: `/Users/scarpenter/.codex/skills/playwright/SKILL.md`)
- prd: Generate a Product Requirements Document (PRD) for a new feature. Use when planning a feature, starting a new project, or when asked to create a PRD.
  Triggers on: create a prd, write prd for, plan this feature, requirements for, spec out. (file: `/Users/scarpenter/.codex/skills/prd/SKILL.md`)
- receiving-code-review: Use when receiving code review feedback, before implementing suggestions, especially if feedback seems unclear or technically
  questionable - requires technical rigor and verification, not performative agreement or blind implementation (file:
  `/Users/scarpenter/.codex/superpowers/skills/receiving-code-review/SKILL.md`)
- requesting-code-review: Use when completing tasks, implementing major features, or before merging to verify work meets requirements (file:
  `/Users/scarpenter/.codex/superpowers/skills/requesting-code-review/SKILL.md`)
- security-best-practices: Perform language and framework specific security best-practice reviews and suggest improvements. Trigger only when the user
  explicitly requests security best practices guidance, a security review/report, or secure-by-default coding help. Trigger only for supported languages (
  python, javascript/typescript, go). Do not trigger for general code review, debugging, or non-security tasks. (file:
  `/Users/scarpenter/.codex/skills/security-best-practices/SKILL.md`)
- security-ownership-map: Analyze git repositories to build a security ownership topology (people-to-file), compute bus factor and sensitive-code ownership, and
  export CSV/JSON for graph databases and visualization. Trigger only when the user explicitly wants a security-oriented ownership or bus-factor analysis
  grounded in git history (for example: orphaned sensitive code, security maintainers, CODEOWNERS reality checks for risk, sensitive hotspots, or ownership
  clusters). Do not trigger for general maintainer lists or non-security ownership questions. (file:
  `/Users/scarpenter/.codex/skills/security-ownership-map/SKILL.md`)
- security-threat-model: Repository-grounded threat modeling that enumerates trust boundaries, assets, attacker capabilities, abuse paths, and mitigations, and
  writes a concise Markdown threat model. Trigger only when the user explicitly asks to threat-model a codebase or path,
  enumerate threats/abuse paths, or
  perform AppSec threat modeling. Do not trigger for general architecture summaries, code review, or non-security design work. (file:
  `/Users/scarpenter/.codex/skills/security-threat-model/SKILL.md`)
- sentry: Use when the user asks to inspect Sentry issues or events, summarize recent production errors, or pull basic Sentry health data via the Sentry API;
  perform read-only queries with the bundled script and require `SENTRY_AUTH_TOKEN`. (file: `/Users/scarpenter/.codex/skills/sentry/SKILL.md`)
- subagent-driven-development: Use when executing implementation plans with independent tasks in the current session (file:
  `/Users/scarpenter/.codex/superpowers/skills/subagent-driven-development/SKILL.md`)
- systematic-debugging: Use when encountering any bug, test failure, or unexpected behavior, before proposing fixes (file:
  `/Users/scarpenter/.codex/superpowers/skills/systematic-debugging/SKILL.md`)
- test-driven-development: Use when implementing any feature or bugfix, before writing implementation code (file:
  `/Users/scarpenter/.codex/superpowers/skills/test-driven-development/SKILL.md`)
- using-git-worktrees: Use when starting feature work that needs isolation from current workspace or before executing implementation plans - creates isolated
  git worktrees with smart directory selection and safety verification (file: `/Users/scarpenter/.codex/superpowers/skills/using-git-worktrees/SKILL.md`)
- using-superpowers: Use when starting any conversation - establishes how to find and use skills, requiring Skill tool invocation before ANY response including
  clarifying questions (file: `/Users/scarpenter/.codex/superpowers/skills/using-superpowers/SKILL.md`)
- verification-before-completion: Use when about to claim work is complete, fixed, or passing, before committing or creating PRs - requires running verification
  commands and confirming output before making any success claims; evidence before assertions always (file:
  `/Users/scarpenter/.codex/superpowers/skills/verification-before-completion/SKILL.md`)
- writing-plans: Use when you have a spec or requirements for a multistep task, before touching code (file:
  `/Users/scarpenter/.codex/superpowers/skills/writing-plans/SKILL.md`)
- writing-skills: Use when creating new skills, editing existing skills, or verifying skills work before deployment (file:
  `/Users/scarpenter/.codex/superpowers/skills/writing-skills/SKILL.md`)
- skill-creator: Guide for creating effective skills. This skill should be used when users want to create a new skill (or update an existing skill) that extends
  Codex's capabilities with specialized knowledge, workflows, or tool integrations. (file: `/Users/scarpenter/.codex/skills/.system/skill-creator/SKILL.md`)
- skill-installer: Install Codex skills into `$CODEX_HOME/skills` from a curated list or a GitHub repo path. Use when a user asks to list installable skills,
  install a curated skill, or install a skill from another repo (including private repos). (file:
  `/Users/scarpenter/.codex/skills/.system/skill-installer/SKILL.md`)

### How to use skills

- Discovery: The list above is the skills available in this session (name + description + file path). Skill bodies live on disk at the listed paths.
- Trigger rules: If the usernames a skill (with `$SkillName` or plain text) OR the task clearly matches a skill's
  description shown above, you must use that
  skill for that turn. Multiple mentions mean use them all. Do not carry skills across turns unless re-mentioned.
- Missing/blocked: If a named skill isn't in the list or the path can't be read, say so briefly and continue with the best fallback.
- How to use a skill (progressive disclosure):
    1) After deciding to use a skill, open its `SKILL.md`. Read only enough to follow the workflow.
    2) When `SKILL.md` references relative paths (e.g., `scripts/foo.py`), resolve them relative to the skill directory listed above first, and only consider
       other paths if needed.
    3) If `SKILL.md` points to extra folders such as `references/`, load only the specific files needed for the request; don't bulk-load everything.
    4) If `scripts/` exist, prefer running or patching them instead of retyping large code blocks.
    5) If `assets/` or templates exist, reuse them instead of recreating from scratch.
- Coordination and sequencing:
    - If multiple skills apply, choose the minimal set that covers the request and state the order you'll use them.
    - Announce which skill(s) you're using and why (one short line). If you skip an obvious skill, say why.
- Context hygiene:
    - Keep context small: summarize long sections instead of pasting them; only load extra files when needed.
    - Avoid deep reference-chasing: prefer opening only files directly linked from `SKILL.md` unless you're blocked.
    - When variants exist (frameworks, providers, domains), pick only the relevant reference file(s) and note that choice.
- Safety and fallback: If a skill can't be applied cleanly (missing files, unclear instructions), state the issue, pick the next-best approach, and continue.

<skills_system priority="1">

## Available Skills

<!-- SKILLS_TABLE_START -->
<usage>
When users ask you to perform tasks, check if any of the available skills below can help complete the task more effectively. Skills provide specialized capabilities and domain knowledge.

How to use skills:

- Invoke: `npx openskills read <skill-name>` (run in your shell)
    - For multiple: `npx openskills read skill-one,skill-two`
- The skill content will load with detailed instructions on how to complete the task
- Base directory provided in output for resolving bundled resources (references/, scripts/, assets/)

Usage notes:

- Only use skills listed in <available_skills> below
- Do not invoke a skill that is already loaded in your context
- Each skill invocation is stateless
  </usage>

<available_skills>

<skill>
<name>canvas-design</name>
<description>Create beautiful visual art in .png and .pdf documents using design philosophy. You should use this skill when the user asks to create a poster, piece of art, design, or other static piece. Create original visual designs, never copying existing artists' work to avoid copyright violations.</description>
<location>project</location>
</skill>

<skill>
<name>claude-api</name>
<description>"Build apps with the Claude API or Anthropic SDK. TRIGGER when: code imports `anthropic`/`@anthropic-ai/sdk`/`claude_agent_sdk`, or user asks to use Claude API, Anthropic SDKs, or Agent SDK. DO NOT TRIGGER when: code imports `openai`/other AI SDK, general programming, or ML/data-science tasks."</description>
<location>project</location>
</skill>

<skill>
<name>docx</name>
<description>"Use this skill whenever the user wants to create, read, edit, or manipulate Word documents (.docx files). Triggers include: any mention of 'Word doc', 'word document', '.docx', or requests to produce professional documents with formatting like tables of contents, headings, page numbers, or letterheads. Also use when extracting or reorganizing content from .docx files, inserting or replacing images in documents, performing find-and-replace in Word files, working with tracked changes or comments, or converting content into a polished Word document. If the user asks for a 'report', 'memo', 'letter', 'template', or similar deliverable as a Word or .docx file, use this skill. Do NOT use for PDFs, spreadsheets, Google Docs, or general coding tasks unrelated to document generation."</description>
<location>project</location>
</skill>

<skill>
<name>find-skills</name>
<description>Helps users discover and install agent skills when they ask questions like "how do I do X", "find a skill for X", "is there a skill that can...", or express interest in extending capabilities. This skill should be used when the user is looking for functionality that might exist as an installable skill.</description>
<location>project</location>
</skill>

<skill>
<name>frontend-design</name>
<description>Create distinctive, production-grade frontend interfaces with high design quality. Use this skill when the user asks to build web components, pages, artifacts, posters, or applications (examples include websites, landing pages, dashboards, React components, HTML/CSS layouts, or when styling/beautifying any web UI). Generates creative, polished code and UI design that avoids generic AI aesthetics.</description>
<location>project</location>
</skill>

<skill>
<name>mcp-builder</name>
<description>Guide for creating high-quality MCP (Model Context Protocol) servers that enable LLMs to interact with external services through well-designed tools. Use when building MCP servers to integrate external APIs or services, whether in Python (FastMCP) or Node/TypeScript (MCP SDK).</description>
<location>project</location>
</skill>

<skill>
<name>pdf</name>
<description>Use this skill whenever the user wants to do anything with PDF files. This includes reading or extracting text/tables from PDFs, combining or merging multiple PDFs into one, splitting PDFs apart, rotating pages, adding watermarks, creating new PDFs, filling PDF forms, encrypting/decrypting PDFs, extracting images, and OCR on scanned PDFs to make them searchable. If the user mentions a .pdf file or asks to produce one, use this skill.</description>
<location>project</location>
</skill>

<skill>
<name>pptx</name>
<description>"Use this skill any time a .pptx file is involved in any way — as input, output, or both. This includes: creating slide decks, pitch decks, or presentations; reading, parsing, or extracting text from any .pptx file (even if the extracted content will be used elsewhere, like in an email or summary); editing, modifying, or updating existing presentations; combining or splitting slide files; working with templates, layouts, speaker notes, or comments. Trigger whenever the user mentions \"deck,\" \"slides,\" \"presentation,\" or references a .pptx filename, regardless of what they plan to do with the content afterward. If a .pptx file needs to be opened, created, or touched, use this skill."</description>
<location>project</location>
</skill>

<skill>
<name>skill-creator</name>
<description>Create new skills, modify and improve existing skills, and measure skill performance. Use when users want to create a skill from scratch, edit, or optimize an existing skill, run evals to test a skill, benchmark skill performance with variance analysis, or optimize a skill's description for better triggering accuracy.</description>
<location>project</location>
</skill>

<skill>
<name>slack-gif-creator</name>
<description>Knowledge and utilities for creating animated GIFs optimized for Slack. Provides constraints, validation tools, and animation concepts. Use when users request animated GIFs for Slack like "make me a GIF of X doing Y for Slack."</description>
<location>project</location>
</skill>

<skill>
<name>template</name>
<description>Replace with description of the skill and when Claude should use it.</description>
<location>project</location>
</skill>

<skill>
<name>theme-factory</name>
<description>Toolkit for styling artifacts with a theme. These artifacts can be slides, docs, reportings, HTML landing pages, etc. There are 10 pre-set themes with colors/fonts that you can apply to any artifact that has been creating, or can generate a new theme on-the-fly.</description>
<location>project</location>
</skill>

<skill>
<name>web-artifacts-builder</name>
<description>Suite of tools for creating elaborate, multi-component claude.ai HTML artifacts using modern frontend web technologies (React, Tailwind CSS, shadcn/ui). Use for complex artifacts requiring state management, routing, or shadcn/ui components - not for simple single-file HTML/JSX artifacts.</description>
<location>project</location>
</skill>

<skill>
<name>webapp-testing</name>
<description>Toolkit for interacting with and testing local web applications using Playwright. Supports verifying frontend functionality, debugging UI behavior, capturing browser screenshots, and viewing browser logs.</description>
<location>project</location>
</skill>

<skill>
<name>xlsx</name>
<description>"Use this skill any time a spreadsheet file is the primary input or output. This means any task where the user wants to: open, read, edit, or fix an existing .xlsx, .xlsm, .csv, or .tsv file (e.g., adding columns, computing formulas, formatting, charting, cleaning messy data); create a new spreadsheet from scratch or from other data sources; or convert between tabular file formats. Trigger especially when the user references a spreadsheet file by name or path — even casually (like \"the xlsx in my downloads\") — and wants something done to it or produced from it. Also trigger for cleaning or restructuring messy tabular data files (malformed rows, misplaced headers, junk data) into proper spreadsheets. The deliverable must be a spreadsheet file. Do NOT trigger when the primary deliverable is a Word document, HTML report, standalone Python script, database pipeline, or Google Sheets API integration, even if tabular data is involved."</description>
<location>project</location>
</skill>

</available_skills>
<!-- SKILLS_TABLE_END -->

</skills_system>
