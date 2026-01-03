# IntelliJ IDEA GitHub Copilot Setup Guide

## Overview

This guide covers the complete setup and configuration of GitHub Copilot in IntelliJ IDEA, including best practices and custom configurations for optimal AI-assisted development.

## Prerequisites

- IntelliJ IDEA 2021.3 or later
- Active GitHub Copilot subscription
- GitHub account with Copilot access

## Installation

### 1. Install GitHub Copilot Plugin

**Via IDE:**
1. Open IntelliJ IDEA
2. Go to `File` → `Settings` (macOS: `IntelliJ IDEA` → `Preferences`)
3. Navigate to `Plugins`
4. Search for "GitHub Copilot"
5. Click `Install`
6. Restart IntelliJ IDEA

**Via Command Line:**
```bash
# Download and install from JetBrains Marketplace
# Plugin ID: com.github.copilot
```

### 2. Authenticate with GitHub

1. After restart, you'll see a notification to sign in
2. Click "Sign in to GitHub"
3. Authorize the application in your browser
4. Return to IntelliJ IDEA

**Manual Authentication:**
1. Go to `Settings` → `Tools` → `GitHub Copilot`
2. Click "Sign in to GitHub"
3. Follow the authentication flow

## Configuration

### Basic Settings

Navigate to `Settings` → `Tools` → `GitHub Copilot`:

#### Enable/Disable Copilot
- **Toggle**: `Settings` → `Tools` → `GitHub Copilot` → Enable GitHub Copilot
- **Keyboard Shortcut**: Set a custom shortcut to quickly enable/disable

#### Suggestion Settings

```
Settings → Tools → GitHub Copilot → Inline Suggestions
```

**Recommended Settings:**
- ✅ Enable inline suggestions
- ✅ Show suggestions automatically
- ✅ Show suggestions for single lines
- ✅ Show suggestions for multiple lines
- Delay before showing suggestions: `100ms` (adjust to preference)

#### Language-Specific Settings

```
Settings → Tools → GitHub Copilot → Language Settings
```

**Enable Copilot for:**
- ✅ Python
- ✅ JavaScript/TypeScript
- ✅ Java
- ✅ Go
- ✅ Terraform
- ✅ YAML/JSON
- ✅ Shell scripts
- ✅ Markdown (for documentation)

**Disable for:**
- ❌ Secrets files (`.env`, credentials)
- ❌ Configuration with sensitive data

### Advanced Settings

#### 1. Copilot Chat Configuration

```
Settings → Tools → GitHub Copilot → Chat
```

**Enable:**
- ✅ Copilot Chat sidebar
- ✅ Inline chat
- ✅ Quick fixes
- ✅ Generate unit tests
- ✅ Explain code

#### 2. Keybindings

```
Settings → Keymap → Plugins → GitHub Copilot
```

**Recommended Keybindings:**

| Action | macOS | Windows/Linux |
|--------|-------|---------------|
| Accept Suggestion | `Tab` | `Tab` |
| Next Suggestion | `Option+]` | `Alt+]` |
| Previous Suggestion | `Option+[` | `Alt+[` |
| Dismiss Suggestion | `Esc` | `Esc` |
| Open Copilot | `Option+Shift+C` | `Alt+Shift+C` |
| Inline Chat | `Cmd+I` | `Ctrl+I` |
| Generate Tests | `Cmd+Shift+T` | `Ctrl+Shift+T` |

**Custom Keybindings Setup:**
```
Settings → Keymap → Search "Copilot"
- Right-click on action
- Select "Add Keyboard Shortcut"
- Press desired key combination
```

#### 3. Content Exclusion

Create a `.copilotignore` file in your project root:

```gitignore
# Sensitive files
.env
.env.*
secrets.yml
credentials.json

# Large data files
*.csv
*.json.gz
data/

# Generated code
build/
dist/
target/

# Dependencies
node_modules/
vendor/
```

Or configure in IntelliJ:
```
Settings → Tools → GitHub Copilot → Content Exclusion
```

Add patterns:
- `**/.env*`
- `**/secrets.*`
- `**/credentials.*`

## Using GitHub Copilot

### 1. Code Completion

**Trigger Suggestions:**
- Start typing - Copilot suggests automatically
- Press `Tab` to accept
- Press `Alt+]` / `Alt+[` to cycle through suggestions

**Best Practices:**
- Write descriptive comments before code
- Use meaningful function/variable names
- Break complex tasks into smaller functions

**Example:**
```python
# Calculate the Fibonacci sequence up to n terms
def fibonacci(n):
    # Copilot will suggest the implementation
```

### 2. Copilot Chat

**Open Chat:**
- Click Copilot icon in sidebar
- Press `Option+Shift+C` (macOS) / `Alt+Shift+C` (Windows/Linux)

**Chat Commands:**
- `/explain` - Explain selected code
- `/fix` - Suggest fixes for errors
- `/tests` - Generate unit tests
- `/doc` - Generate documentation

**Example Usage:**
```
# Select a function, then in chat:
/tests
# Copilot generates comprehensive test cases

/explain
# Copilot provides detailed explanation

/doc
# Copilot writes documentation
```

### 3. Inline Chat

**Usage:**
1. Select code
2. Press `Cmd+I` (macOS) / `Ctrl+I` (Windows/Linux)
3. Type your request
4. Copilot modifies code inline

**Common Requests:**
- "Add error handling"
- "Refactor to use async/await"
- "Add type hints"
- "Optimize performance"

### 4. Generate Tests

**Quick Test Generation:**
1. Place cursor in function
2. Press `Cmd+Shift+T` (macOS) / `Ctrl+Shift+T` (Windows/Linux)
3. Copilot generates test file with test cases

**Or via Chat:**
```
Select function → Chat → /tests
```

## Terraform-Specific Configuration

For Terraform development, configure Copilot with custom instructions:

### 1. Project-Level Instructions

Create `.github/copilot-instructions.md` in project root:

```markdown
## Terraform Best Practices

- Use Terraform 1.5+ features
- Always include provider version constraints
- Use data sources for existing resources
- Implement proper state management
- Add comprehensive variable descriptions
- Use modules for reusable components
- Follow naming conventions: lowercase with underscores
- Add tags to all resources
- Use locals for computed values
- Implement proper error handling
```

### 2. Terraform Plugin Settings

```
Settings → Languages & Frameworks → Terraform
```

**Enable:**
- ✅ Terraform/HCL support
- ✅ Enable inspection
- ✅ Code completion
- ✅ External format tool (terraform fmt)

### 3. Terraform Copilot Patterns

**Variable Definitions:**
```hcl
# Copilot will suggest based on this pattern:
variable "environment" {
  # Type description and Copilot completes
```

**Resource Creation:**
```hcl
# Create an S3 bucket with encryption and versioning
resource "aws_s3_bucket" "data" {
  # Copilot suggests best practices
```

## Best Practices

### 1. Code Review
- Always review generated code
- Verify security implications
- Check for performance issues
- Ensure code follows team standards

### 2. Privacy
- Disable Copilot for repositories with sensitive data
- Use content exclusion for confidential files
- Review what data is sent to GitHub

### 3. Learning
- Use `/explain` to understand generated code
- Compare suggestions to learn patterns
- Ask for alternatives with chat

### 4. Performance
- Disable for very large files (>10,000 lines)
- Clear cache if suggestions slow down:
  ```
  Settings → Tools → GitHub Copilot → Clear Cache
  ```

### 5. Team Settings

For team consistency, share:
- `.copilotignore` in repository
- `.github/copilot-instructions.md` for project guidelines
- Keybinding recommendations in team docs

## Troubleshooting

### Copilot Not Working

**Check Authentication:**
```
Settings → Tools → GitHub Copilot → Sign Out → Sign In
```

**Verify Subscription:**
- Visit [github.com/settings/copilot](https://github.com/settings/copilot)
- Ensure subscription is active

**Check Network:**
- Verify proxy settings if behind corporate firewall
- Ensure `api.github.com` is accessible

### No Suggestions Appearing

1. **Check if enabled**: Look for Copilot icon in status bar
2. **File type supported**: Verify language is enabled
3. **Content not excluded**: Check `.copilotignore`
4. **Restart IDE**: Sometimes needed after configuration changes

### Slow Performance

1. **Reduce suggestion delay**: `Settings` → `Tools` → `GitHub Copilot` → Increase delay
2. **Disable for large files**: Right-click status bar icon
3. **Clear cache**: `Settings` → `Tools` → `GitHub Copilot` → Clear Cache
4. **Update plugin**: Check for plugin updates

### Authentication Issues

**Re-authenticate:**
```bash
# macOS/Linux - clear cached tokens
rm -rf ~/.config/github-copilot/

# Windows
del /s /q %USERPROFILE%\.config\github-copilot\
```

Then sign in again in IntelliJ IDEA.

## Updates and Maintenance

### Plugin Updates

```
Settings → Plugins → Installed → GitHub Copilot → Update
```

**Enable auto-updates:**
```
Settings → Appearance & Behavior → System Settings → Updates
- Check for plugin updates: Daily
- ✅ Automatically check updates for: Custom plugin repositories
```

### Monitor Usage

View your Copilot usage:
- [github.com/settings/copilot](https://github.com/settings/copilot)
- Check acceptance rate
- Review suggestions quality

## Integration with Other Tools

### Version Control
- Copilot integrates with Git in IntelliJ
- Generates commit messages
- Suggests code review comments

### Database Tools
- Use with IntelliJ Database Tools
- Generate SQL queries
- Create migrations

### Terminal
- Use Copilot CLI separately (see [copilot-cli-setup.md](./copilot-cli-setup.md))
- Terminal suggestions available with CLI tool

## Additional Resources

- [GitHub Copilot Documentation](https://docs.github.com/en/copilot)
- [IntelliJ IDEA Copilot Plugin](https://plugins.jetbrains.com/plugin/17718-github-copilot)
- [Copilot Trust Center](https://github.com/features/copilot/trust-center)
- [Custom Instructions Guide](./terraform-instructions.md)
