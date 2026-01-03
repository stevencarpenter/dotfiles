# OpenAI Codex CLI Setup Guide

## Overview

OpenAI Codex CLI provides command-line access to OpenAI's Codex models, enabling natural language to code generation, code explanation, and more. This guide covers setup and integration with your development workflow.

## Prerequisites

- OpenAI API account with access to Codex/GPT models
- Python 3.8+ or Node.js 18+
- API key from OpenAI

## Getting API Access

### 1. Create OpenAI Account

1. Visit [platform.openai.com](https://platform.openai.com/)
2. Sign up or log in
3. Navigate to API Keys section

### 2. Generate API Key

```
Settings → API Keys → Create new secret key
```

**Save your key securely** - it won't be shown again!

### 3. Set Environment Variable

Add to `~/.zshenv` or `~/.config/zsh/.zshrc`:

```bash
# OpenAI API Configuration
export OPENAI_API_KEY="sk-proj-xxxxxxxxxxxxxxxxxxxxx"
export OPENAI_MODEL="gpt-4"  # or "gpt-3.5-turbo", "gpt-4-turbo"
```

**Reload shell:**
```bash
source ~/.zshenv
```

## Installation Methods

### Method 1: Shell Script (Recommended)

Create `~/scripts/codex.sh`:

```bash
#!/bin/bash
# OpenAI Codex CLI wrapper

OPENAI_API_KEY="${OPENAI_API_KEY}"
MODEL="${OPENAI_MODEL:-gpt-4}"

if [ -z "$OPENAI_API_KEY" ]; then
    echo "Error: OPENAI_API_KEY not set"
    exit 1
fi

codex_query() {
    local prompt="$1"
    local system_msg="${2:-You are a helpful coding assistant.}"

    curl -s https://api.openai.com/v1/chat/completions \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $OPENAI_API_KEY" \
        -d "{
            \"model\": \"$MODEL\",
            \"messages\": [
                {\"role\": \"system\", \"content\": \"$system_msg\"},
                {\"role\": \"user\", \"content\": \"$prompt\"}
            ],
            \"temperature\": 0.7,
            \"max_tokens\": 2000
        }" | jq -r '.choices[0].message.content'
}

case "$1" in
    suggest)
        shift
        codex_query "$*" "You are an expert programmer. Provide code suggestions."
        ;;
    explain)
        shift
        codex_query "$*" "You are a code explainer. Explain the following code clearly."
        ;;
    fix)
        shift
        codex_query "$*" "You are a debugging expert. Fix the following code."
        ;;
    optimize)
        shift
        codex_query "$*" "You are a performance expert. Optimize the following code."
        ;;
    test)
        shift
        codex_query "$*" "You are a test writer. Generate comprehensive tests for the following code."
        ;;
    doc)
        shift
        codex_query "$*" "You are a documentation writer. Write clear documentation for the following code."
        ;;
    *)
        codex_query "$*"
        ;;
esac
```

**Make executable:**
```bash
chmod +x ~/scripts/codex.sh
```

**Add alias to `~/.config/zsh/.zshrc`:**
```bash
alias codex='~/scripts/codex.sh'
alias cx='~/scripts/codex.sh'
```

### Method 2: Python CLI Tool

Create `~/scripts/codex-cli.py`:

```python
#!/usr/bin/env python3
"""
OpenAI Codex CLI Tool
"""
import os
import sys
import argparse
from openai import OpenAI

# Initialize OpenAI client
client = OpenAI(api_key=os.getenv('OPENAI_API_KEY'))
MODEL = os.getenv('OPENAI_MODEL', 'gpt-4')

def query_codex(prompt, system_message=None, temperature=0.7, max_tokens=2000):
    """Query OpenAI API"""
    messages = []

    if system_message:
        messages.append({"role": "system", "content": system_message})

    messages.append({"role": "user", "content": prompt})

    try:
        response = client.chat.completions.create(
            model=MODEL,
            messages=messages,
            temperature=temperature,
            max_tokens=max_tokens
        )
        return response.choices[0].message.content
    except Exception as e:
        return f"Error: {str(e)}"

def main():
    parser = argparse.ArgumentParser(description='OpenAI Codex CLI')
    parser.add_argument('command', nargs='?', default='ask',
                       choices=['suggest', 'explain', 'fix', 'optimize', 'test', 'doc', 'ask'],
                       help='Command to execute')
    parser.add_argument('prompt', nargs='+', help='Prompt for Codex')
    parser.add_argument('-m', '--model', default=MODEL, help='Model to use')
    parser.add_argument('-t', '--temperature', type=float, default=0.7,
                       help='Temperature (0.0-2.0)')

    args = parser.parse_args()
    prompt = ' '.join(args.prompt)

    system_messages = {
        'suggest': 'You are an expert programmer. Provide clear code suggestions.',
        'explain': 'You are a code explainer. Explain code clearly and concisely.',
        'fix': 'You are a debugging expert. Identify and fix issues in code.',
        'optimize': 'You are a performance expert. Optimize code for efficiency.',
        'test': 'You are a test engineer. Generate comprehensive test cases.',
        'doc': 'You are a technical writer. Write clear, helpful documentation.',
        'ask': 'You are a helpful coding assistant.'
    }

    system_msg = system_messages.get(args.command)
    result = query_codex(prompt, system_msg, args.temperature)
    print(result)

if __name__ == '__main__':
    main()
```

**Install dependencies:**
```bash
pip install openai
```

**Make executable:**
```bash
chmod +x ~/scripts/codex-cli.py
```

**Add alias:**
```bash
alias codex='python3 ~/scripts/codex-cli.py'
```

### Method 3: Node.js CLI Tool

Install official OpenAI SDK:

```bash
npm install -g openai

# Or for project
npm install openai
```

Create `~/scripts/codex.js`:

```javascript
#!/usr/bin/env node

const { OpenAI } = require('openai');

const openai = new OpenAI({
    apiKey: process.env.OPENAI_API_KEY
});

const MODEL = process.env.OPENAI_MODEL || 'gpt-4';

async function queryCodex(prompt, systemMessage, temperature = 0.7) {
    try {
        const response = await openai.chat.completions.create({
            model: MODEL,
            messages: [
                { role: 'system', content: systemMessage },
                { role: 'user', content: prompt }
            ],
            temperature: temperature,
            max_tokens: 2000
        });

        return response.choices[0].message.content;
    } catch (error) {
        console.error('Error:', error.message);
        process.exit(1);
    }
}

const systemMessages = {
    suggest: 'You are an expert programmer. Provide clear code suggestions.',
    explain: 'You are a code explainer. Explain code clearly.',
    fix: 'You are a debugging expert. Fix issues in code.',
    optimize: 'You are a performance expert. Optimize code.',
    test: 'You are a test engineer. Generate comprehensive tests.',
    doc: 'You are a technical writer. Write clear documentation.'
};

const command = process.argv[2];
const prompt = process.argv.slice(3).join(' ');

if (!prompt) {
    console.error('Usage: codex [command] <prompt>');
    process.exit(1);
}

const systemMsg = systemMessages[command] || 'You are a helpful coding assistant.';

queryCodex(prompt, systemMsg)
    .then(result => console.log(result))
    .catch(error => console.error('Error:', error));
```

**Make executable:**
```bash
chmod +x ~/scripts/codex.js
```

## Usage

### Basic Commands

```bash
# General query
codex "write a function to reverse a string in Python"

# Code suggestions
codex suggest "create a REST API endpoint for user authentication"

# Explain code
codex explain "def factorial(n): return 1 if n <= 1 else n * factorial(n-1)"

# Fix bugs
codex fix "my loop runs infinitely: while True: print('hello')"

# Optimize code
codex optimize "for i in range(len(arr)): for j in range(len(arr)): if arr[i] > arr[j]: swap"

# Generate tests
codex test "def add(a, b): return a + b"

# Write documentation
codex doc "class UserManager: def __init__(self): self.users = []"
```

### Advanced Usage

#### 1. Pipe Code to Codex

```bash
# Explain code from file
cat script.py | codex explain

# Generate tests for function
grep -A 10 "def calculate" app.py | codex test

# Fix code in file
codex fix "$(cat buggy.py)"
```

#### 2. Interactive Mode

Create `~/scripts/codex-interactive.sh`:

```bash
#!/bin/bash
# Interactive Codex session

echo "Codex Interactive Mode (type 'exit' to quit)"
echo "Commands: suggest, explain, fix, optimize, test, doc"
echo ""

while true; do
    echo -n "codex> "
    read -r input

    if [ "$input" = "exit" ]; then
        break
    fi

    codex $input
    echo ""
done
```

**Usage:**
```bash
chmod +x ~/scripts/codex-interactive.sh
~/scripts/codex-interactive.sh
```

#### 3. Vim/Neovim Integration

Add to `~/.config/nvim/lua/config/keymaps.lua`:

```lua
-- Codex integration
vim.keymap.set('v', '<leader>ce', function()
    local selection = vim.fn.getline("'<", "'>")
    local code = table.concat(selection, "\n")
    local cmd = string.format("!codex explain '%s'", code)
    vim.cmd(cmd)
end, { desc = "Explain code with Codex" })

vim.keymap.set('v', '<leader>cf', function()
    local selection = vim.fn.getline("'<", "'>")
    local code = table.concat(selection, "\n")
    local cmd = string.format("!codex fix '%s'", code)
    vim.cmd(cmd)
end, { desc = "Fix code with Codex" })
```

#### 4. VS Code Integration

Install REST Client extension, then create `.vscode/codex.http`:

```http
### Codex Query
POST https://api.openai.com/v1/chat/completions
Authorization: Bearer {{$processEnv OPENAI_API_KEY}}
Content-Type: application/json

{
    "model": "gpt-4",
    "messages": [
        {
            "role": "system",
            "content": "You are a helpful coding assistant."
        },
        {
            "role": "user",
            "content": "Your query here"
        }
    ],
    "temperature": 0.7
}
```

## Shell Aliases and Functions

Add to `~/.config/zsh/.zshrc`:

```bash
# ============================================
# OpenAI Codex CLI Shortcuts
# ============================================

# Basic aliases
alias cx='codex'
alias cxs='codex suggest'
alias cxe='codex explain'
alias cxf='codex fix'
alias cxo='codex optimize'
alias cxt='codex test'
alias cxd='codex doc'

# Advanced functions
cxfile() {
    # Process entire file
    local file="$1"
    local command="${2:-explain}"

    if [ ! -f "$file" ]; then
        echo "File not found: $file"
        return 1
    fi

    codex "$command" "$(cat "$file")"
}

cxdiff() {
    # Explain git diff
    git diff "$@" | codex explain
}

cxcommit() {
    # Generate commit message
    git diff --cached | codex "Write a concise git commit message for these changes"
}

cxpr() {
    # Generate PR description
    git log origin/main..HEAD --oneline | codex "Write a pull request description for these commits"
}
```

## Language-Specific Tips

### Python

```bash
# Generate Python docstrings
codex doc "def process_data(df, columns): return df[columns].dropna()"

# Create type hints
codex "add type hints to: def calc(a, b): return a + b"

# Write unit tests
codex test "class Calculator: def add(self, a, b): return a + b"
```

### Terraform

```bash
# Generate Terraform resources
codex suggest "terraform resource for S3 bucket with encryption and versioning"

# Explain HCL
codex explain "$(cat main.tf)"

# Optimize Terraform
codex optimize "my terraform takes 10 minutes to apply"
```

### JavaScript/TypeScript

```bash
# Convert JS to TS
codex "convert to TypeScript: function add(a, b) { return a + b; }"

# Generate async version
codex "make this async: function fetchData() { return getData(); }"

# Create tests
codex test "export function validateEmail(email) { return /\S+@\S+\.\S+/.test(email); }"
```

### Shell Scripts

```bash
# Generate shell script
codex suggest "bash script to backup database with rotation"

# Explain complex command
codex explain "find . -name '*.log' -mtime +30 -exec rm {} \;"

# Optimize script
cxfile slow-script.sh optimize
```

## Best Practices

### 1. Context Matters

```bash
# Good - includes context
codex "in Python 3.11, write a function to parse JSON with error handling"

# Less specific
codex "write JSON parser"
```

### 2. Iterative Refinement

```bash
# Start broad
codex suggest "API endpoint"

# Refine
codex suggest "FastAPI endpoint for user authentication with JWT"
```

### 3. Code Review

- Always review generated code
- Test before using in production
- Verify security implications
- Check for best practices

### 4. Cost Management

```bash
# Use cheaper models for simple tasks
export OPENAI_MODEL="gpt-3.5-turbo"

# Monitor usage
# Visit: https://platform.openai.com/usage
```

### 5. Security

```bash
# Never include secrets in prompts
# Bad:
codex "connect to DB: postgresql://user:password@host/db"

# Good:
codex "connect to postgres DB using environment variables"
```

## Rate Limits and Costs

### Model Pricing (as of 2024)

| Model | Input | Output |
|-------|-------|--------|
| GPT-4 | $0.03/1K tokens | $0.06/1K tokens |
| GPT-4 Turbo | $0.01/1K tokens | $0.03/1K tokens |
| GPT-3.5 Turbo | $0.0005/1K tokens | $0.0015/1K tokens |

### Rate Limits

- Free tier: Limited requests per minute
- Paid tier: Higher limits based on usage history

**Check your limits:**
```bash
curl https://api.openai.com/v1/models \
    -H "Authorization: Bearer $OPENAI_API_KEY"
```

### Cost Optimization

```bash
# Use streaming for long responses
# Set max_tokens appropriately
# Cache common queries locally
# Use GPT-3.5 for simpler tasks
```

## Troubleshooting

### API Key Issues

```bash
# Verify key is set
echo $OPENAI_API_KEY

# Test API access
curl https://api.openai.com/v1/models \
    -H "Authorization: Bearer $OPENAI_API_KEY"
```

### Rate Limiting

```bash
# Error: Rate limit exceeded
# Solution: Wait or upgrade account

# Implement retry logic
codex() {
    local max_retries=3
    local retry_delay=5

    for i in $(seq 1 $max_retries); do
        result=$(~/scripts/codex.sh "$@" 2>&1)

        if [[ ! "$result" =~ "rate_limit" ]]; then
            echo "$result"
            return 0
        fi

        echo "Rate limited, retrying in ${retry_delay}s..." >&2
        sleep $retry_delay
    done

    echo "Failed after $max_retries attempts" >&2
    return 1
}
```

### Network Issues

```bash
# Configure proxy
export HTTPS_PROXY="http://proxy.example.com:8080"

# Increase timeout
curl --max-time 60 ...
```

### Response Quality

```bash
# Adjust temperature (0.0-2.0)
# Lower = more focused
# Higher = more creative

# In Python script:
codex -t 0.2 "precise calculation function"
codex -t 1.5 "creative story generator"
```

## Advanced Integration

### Git Hooks

Create `.git/hooks/pre-commit`:

```bash
#!/bin/bash
# Generate commit message with Codex

if [ -z "$(git diff --cached)" ]; then
    exit 0
fi

# Generate message
msg=$(git diff --cached | codex "Write a concise commit message")

# Show and confirm
echo "Suggested commit message:"
echo "$msg"
echo ""
read -p "Use this message? (y/n) " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
    git commit -m "$msg"
    exit 0
fi

exit 1
```

### CI/CD Integration

```yaml
# .github/workflows/codex-review.yml
name: AI Code Review

on: [pull_request]

jobs:
  review:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Review with Codex
        env:
          OPENAI_API_KEY: ${{ secrets.OPENAI_API_KEY }}
        run: |
          # Get diff and review
          git diff origin/main...HEAD > changes.diff

          # Send to Codex for review
          curl -X POST https://api.openai.com/v1/chat/completions \
            -H "Authorization: Bearer $OPENAI_API_KEY" \
            -d "{ /* review request */ }"
```

## Additional Resources

- [OpenAI API Documentation](https://platform.openai.com/docs)
- [Codex Best Practices](https://platform.openai.com/docs/guides/code)
- [OpenAI Cookbook](https://github.com/openai/openai-cookbook)
- [Rate Limits](https://platform.openai.com/docs/guides/rate-limits)

## See Also

- [GitHub Copilot CLI Setup](./copilot-cli-setup.md)
- [IntelliJ IDEA Copilot Setup](./intellij-copilot-setup.md)
- [MCP Setup Guide](./mcp-setup.md)
- [Terraform Instructions](./terraform-instructions.md)
