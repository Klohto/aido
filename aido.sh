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

QUERY_ALLOWED="true"
QUERY="$@"
# echo $QUERY

# Initialize conversation history
MESSAGES='[]'

while true; do
    # fast and ugly, we need to control whether we allow query to get from more complex gum confirm / redo / retry logic flows
    if [[ $QUERY_ALLOWED == "true" ]]; then
        if [ -z "$QUERY" ]; then
        # long form or use "$(cat <<'EOF' input input input EOF
        # )"
            QUERY=$(gum write --no-show-help --placeholder "What do you want to do?" --cursor.foreground "#E6D3A7")
        fi

        printf '%s\n' "$QUERY" | gum style --border "none" --padding "0 0" --italic --foreground "#E6D3A7"

        # Properly escape the query for JSON
        ESCAPED_QUERY=$(printf '%s\n' "$QUERY" | jq -Rs .)

        # Add current query to messages
        MESSAGES=$(printf '%s\n' "$MESSAGES" | jq ". + [{\"role\": \"user\", \"content\": $ESCAPED_QUERY}]")

        SYSTEM_MESSAGE=$(cat <<EOF
        Give a $(basename $SHELL) shell one-liner to answer the question.
        The command will run on $(uname -s -r -m).
        Do not use a code block or leading/trailing backticks.
        Follow the users instructions for extra details.
        If given a complex query that requires a explanation, respond as a comment to not interfere with the command output.
EOF
        )

        CONVERSATION=$(cat <<EOF
            {
                "model": "claude-opus-4-20250514",
                "max_tokens": 32000,
                "system": $(printf '%s' "$SYSTEM_MESSAGE" | jq -Rs .),
                "messages": $MESSAGES
            }
EOF
        )

        RESPONSE=$(gum spin -s 'moon' --title.foreground "#7A6C5F" --title ${SPINNER_OPTIONS[$((RANDOM % ${#SPINNER_OPTIONS[@]}))]} --show-output -- \
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
        ESCAPED_RESPONSE=$(printf '%s\n' "$RESPONSE" | jq -Rs .)

        # Add assistant response to messages
        MESSAGES=$(printf '%s\n' "$MESSAGES" | jq ". + [{\"role\": \"assistant\", \"content\": $ESCAPED_RESPONSE}]")

        printf '%s\n' "$RESPONSE" | gum style --border "none" --padding "0 0" --foreground "#CD7C5D"
    fi

    # refresh the variable
    QUERY_ALLOWED=true

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
            # Up arrow - Copy
            CHOICE=$(printf "󰆏 Copy\n󰌑 Run\n󰑖 Redo" | gum choose --no-show-help --height 3 --cursor.foreground "#7A6C5F" --header '' --selected 'Copy')
        elif [[ $key == $'\e[B' ]]; then
            CHOICE=$(printf "󰆏 Copy\n󰌑 Run\n󰑖 Redo" | gum choose --no-show-help --height 3 --cursor.foreground "#7A6C5F" --header '' --selected 'Redo')
        else
            # Enter - default to Run
            CHOICE="󰌑 Run"
        fi
    else
        # Any other key - use gum input for extending conversation
        CHOICE=$(echo -n "$key" | gum input --char-limit=0 --cursor.foreground "#E6D3A7" --no-show-help --placeholder "Add details to refine the command...")
    fi

    # Cancelling any gum action leaves the CHOICE empty, we want to return to handle the other key events
    if [[ $CHOICE == "" ]]; then
        QUERY_ALLOWED="false"
    fi

    case $CHOICE in
        "󰌑 Run")
            CURRENT_SHELL=$(ps -o comm= -p $PPID)
            case $CURRENT_SHELL in
                *zsh)
                    # we want the exact command including the quotes to be saved in history
                    ESCAPED_CMD=$(printf %q "$RESPONSE")
                    zsh -ic "print -s -- $ESCAPED_CMD"
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
        "󰑖 Redo")
            # Keep the same query, messages will be rebuilt
            MESSAGES=$(printf '%s\n' "$MESSAGES" | jq '.[:-2]')
            continue
            ;;
        "󰆏 Copy")
            printf '%s\n' "$RESPONSE" | if command -v pbcopy >/dev/null; then pbcopy
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
