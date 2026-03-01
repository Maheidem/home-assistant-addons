#!/bin/bash

# Claude Session Picker - Interactive menu for choosing Claude session type
# Provides options for new session, continue, resume, manual command, or regular shell

show_banner() {
    clear
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                    🤖 Claude Terminal                        ║"
    echo "║                   Interactive Session Picker                ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
}

show_menu() {
    echo "Choose your Claude session type:"
    echo ""
    echo "  1) 🆕 New interactive session (default)"
    echo "  2) ⏩ Continue most recent conversation (-c)"
    echo "  3) 📋 Resume from conversation list (-r)"
    echo "  4) ⚙️  Custom Claude command (manual flags)"
    echo "  5) 🐚 Drop to bash shell"
    echo "  6) ❌ Exit"
    echo ""
}

get_user_choice() {
    local choice
    # Send prompt to stderr to avoid capturing it with the return value
    printf "Enter your choice [1-6] (default: 1): " >&2
    read -r choice

    # Default to 1 if empty
    if [ -z "$choice" ]; then
        choice=1
    fi

    # Trim whitespace and return only the choice
    choice=$(echo "$choice" | tr -d '[:space:]')
    echo "$choice"
}

launch_claude_new() {
    echo "🚀 Starting new Claude session..."
    exec claude
}

launch_claude_continue() {
    echo "⏩ Continuing most recent conversation..."
    exec claude -c
}

launch_claude_resume() {
    echo "📋 Opening conversation list for selection..."
    exec claude -r
}

launch_claude_custom() {
    echo ""
    echo "Enter your Claude command (e.g., 'claude --help' or 'claude -p \"hello\"'):"
    echo "Available flags: -c (continue), -r (resume), -p (print), --model, etc."
    echo -n "> claude "
    read -r custom_args

    if [ -z "$custom_args" ]; then
        echo "No arguments provided. Starting default session..."
        launch_claude_new
    else
        echo "🚀 Running: claude $custom_args"
        # Use read -a to split args safely; exec replaces the shell with no eval needed
        read -ra args_array <<< "$custom_args"
        exec claude "${args_array[@]}"
    fi
}

launch_bash_shell() {
    echo "🐚 Dropping to bash shell..."
    echo "Tip: Run 'claude' manually when ready"
    exec bash
}

exit_session_picker() {
    echo "👋 Goodbye!"
    exit 0
}

# Handle signals — only INT/TERM trigger goodbye, not normal EXIT
# This prevents the trap from hiding errors when exec fails
trap 'echo "👋 Goodbye!"; exit 0' INT TERM

# Main execution flow
main() {
    while true; do
        show_banner
        show_menu
        choice=$(get_user_choice)

        case "$choice" in
            1)
                launch_claude_new
                ;;
            2)
                launch_claude_continue
                ;;
            3)
                launch_claude_resume
                ;;
            4)
                launch_claude_custom
                ;;
            5)
                launch_bash_shell
                ;;
            6)
                exit_session_picker
                ;;
            *)
                echo ""
                echo "❌ Invalid choice: '$choice'"
                echo "Please select a number between 1-6"
                echo ""
                printf "Press Enter to continue..." >&2
                read -r
                ;;
        esac
    done
}

# Run main function
main "$@"
