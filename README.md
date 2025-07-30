# Aido

A command-line tool that converts natural language queries into shell commands using Claude API.

## What it does

Aido takes your plain English request and generates a shell command to accomplish the task. You can then run it, copy it, or refine it further through conversation.

## Prerequisites

- `gum` - for interactive UI
- `jq` - for JSON processing
- `curl` - for API calls
- An Anthropic API key

## Setup

1. Install dependencies:
   ```bash
   brew install gum jq
   ```

2. Set your API key:
   ```bash
   export ANTHROPIC_API_KEY="your-api-key-here"
   ```

3. Add an alias for your shell:
   - **ZSH**: `alias aido='noglob ./aido.sh'`
   - **Bash**: `alias aido='./aido.sh'`
   - **Fish**: `alias aido './aido.sh'`

3a. Setup .zshrc:
   ```bash
   # comments arent evaluated as commands in interactive shell
   setopt interactive_comments
   alias aido='noglob command aido/aido.sh
   ```

## Usage

```bash
# Direct query
aido find all python files modified today

# Interactive mode (opens text editor)
aido
```

## Controls

After getting a response:
- **Enter** - Run the command
- **Up/Down Arrow** - Run/Copy/Regenerate selection
- **Input** - Continue the conversation with additional details
