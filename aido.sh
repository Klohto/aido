#!/bin/bash
COLORTERM=truecolor
CLICOLOR_FORCE=1

# evaluate that gum and jq is installed
command -v gum >/dev/null 2>&1 || { echo >&2 "gum is not installed. Please install it."; exit 1; }
command -v jq >/dev/null 2>&1 || { echo >&2 "jq is not installed. Please install it."; exit 1; }

SPINNER_OPTIONS=(Thinking... Manifesting... Providing... Creating... Prompting... Wizarding...)
# echo ${SPINNER_OPTIONS[$((RANDOM % ${#SPINNER_OPTIONS[@]}))]}

# Set up trap for CTRL+C
trap 'echo ""; exit 0' INT

QUERY="$@"
# echo $QUERY

# Initialize conversation history
MESSAGES='[]'

while true; do
    echo $QUERY | gum style --border "rounded" --padding "0 2" --italic --foreground 444 --border-foreground 444
    if [ -z "$QUERY" ] && [ $# -eq 0 ]; then
        QUERY=$(gum input --placeholder "What do you want to do?")
    fi

    # Properly escape the query for JSON
    ESCAPED_QUERY=$(echo "$QUERY" | jq -Rs .)

    # Add current query to messages
    MESSAGES=$(echo "$MESSAGES" | jq ". + [{\"role\": \"user\", \"content\": $ESCAPED_QUERY}]")

    CONVERSATION=$(cat <<EOF
        {
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 2048,
            "system": "Give a $(basename $SHELL) shell one-liner to answer the question. The command will run on $(uname -s -r -m). Do not use a code block or leading/trailing backticks. Follow the users instructions for extra details. If given a complex query that requires a explanation, respond as a comment to not interfere with the command output.",
            "messages": $MESSAGES
        }
EOF
    )

    RESPONSE=$(gum spin -s 'moon' --title ${SPINNER_OPTIONS[$((RANDOM % ${#SPINNER_OPTIONS[@]}))]} -- \
        curl \
        --silent \
        --url "https://api.anthropic.com/v1/messages" \
        --header "X-Api-Key: $ANTHROPIC_API_KEY" \
        --header "Anthropic-Version: 2023-06-01" \
        --header "Content-Type: application/json" \
        --json "$CONVERSATION" \
        | jq -r '.content[0].text // empty'
    )

    # Check if response is empty or null
    if [ -z "$RESPONSE" ]; then
        echo "Error: No response from API. Please check your API key and connection."
        exit 1
    fi

    # Properly escape the response for JSON
    ESCAPED_RESPONSE=$(echo "$RESPONSE" | jq -Rs .)

    # Add assistant response to messages
    MESSAGES=$(echo "$MESSAGES" | jq ". + [{\"role\": \"assistant\", \"content\": $ESCAPED_RESPONSE}]")

    echo "$RESPONSE" | gum style --border "rounded" --padding "0 2" --foreground 222 --border-foreground 222

    # Show instructions
    # echo "Use ↑↓ arrows + Enter to select, or start typing to add details"

    # Read single character to determine input mode
    read -n1 -s key

    # Check if it's an arrow key or enter
    if [[ $key == $'\e' ]]; then
        # It's an escape sequence (arrow key), read the rest
        read -n2 -s rest
        key+=$rest
    fi

    # If it's an arrow key or enter, use gum choose
    if [[ $key == $'\e[A' ]] || [[ $key == $'\e[B' ]] || [[ $key == "" ]]; then
        # Put the key back for gum to handle
        if [[ $key == $'\e[A' ]]; then
            # Up arrow - start with Redo selected
            CHOICE=$(echo -e "Run\nRedo\nCopy" | gum choose --no-show-help --selected="Copy")
        elif [[ $key == $'\e[B' ]]; then
            # Down arrow - start with Redo selected
            CHOICE=$(echo -e "Run\nRedo\nCopy" | gum choose --no-show-help --selected="Redo")
        else
            # Enter - default to Run
            CHOICE=$(echo -e "Run")
        fi
    else
        # Any other key - use gum input for extending conversation
        CHOICE=$(echo -n "$key" | gum input --placeholder "Add details to refine the command...")
    fi

    case $CHOICE in
        Run)
            CURRENT_SHELL=$(ps -o comm= -p $PPID)
            case $CURRENT_SHELL in
                *zsh)
                    # echo "Executing in zsh"
                    zsh -c "noglob print -rz -- \"$RESPONSE\""
                    ;;
                *bash)
                    history -s "$RESPONSE"
                    ;;
                *fish)
                    history append "$RESPONSE"
                    ;;
            esac

            eval "$RESPONSE" || {
                printf 'Command failed: %s\n' "$RESPONSE" >&2
            }
            break
            ;;
        Redo)
            # Keep the same query, messages will be rebuilt
            MESSAGES=$(echo "$MESSAGES" | jq '.[:-2]')
            continue
            ;;
        Copy)
            echo "$RESPONSE" | if command -v pbcopy >/dev/null; then pbcopy
            elif command -v xclip >/dev/null; then xclip -selection clipboard
            elif command -v wl-copy >/dev/null; then wl-copy
            elif command -v xsel >/dev/null; then xsel --clipboard --input
            else
                printf 'No clipboard utility found (install xclip, wl-clipboard, or xsel).\n' >&2
                exit 1
            fi
            break
            ;;
        *)
            # Any other text is treated as extending the conversation
            if [ -n "$CHOICE" ]; then
                QUERY="$CHOICE"
            else
                continue
            fi
            ;;
    esac
done
