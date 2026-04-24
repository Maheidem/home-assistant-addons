# OpenCode add-on bash defaults — loaded via /etc/profile.d/ on every interactive shell.
# Only relevant if opencode web crashes and the user shells in for debugging.

# --- PATH -------------------------------------------------------------------
# Debian's /etc/profile resets root's PATH; put the extra dirs back.
case ":${PATH}:" in
    *":/root/.local/bin:"*) ;;
    *) export PATH="/root/.local/bin:/usr/local/bin:${PATH}" ;;
esac

# --- History ----------------------------------------------------------------
HISTSIZE=10000
HISTFILESIZE=20000
HISTCONTROL=ignoreboth
shopt -s histappend
shopt -s checkwinsize

# --- Prompt -----------------------------------------------------------------
__git_branch() {
    local b
    b=$(git symbolic-ref --short HEAD 2>/dev/null) || b=$(git rev-parse --short HEAD 2>/dev/null) || return
    printf ' (%s)' "${b}"
}
PS1='\[\e[36m\]\u@opencode\[\e[0m\]:\[\e[34m\]\w\[\e[33m\]$(__git_branch)\[\e[0m\]\n\$ '

# --- Aliases ----------------------------------------------------------------
alias ls='ls --color=auto'
alias ll='ls -lah --color=auto'
alias la='ls -lA --color=auto'
alias l='ls --color=auto'
alias grep='grep --color=auto'
alias egrep='egrep --color=auto'
alias fgrep='fgrep --color=auto'
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'

# --- Defaults ---------------------------------------------------------------
export EDITOR=nano
export VISUAL=nano
export PAGER=less
export LESS='-R -M -i -F -X'

# --- Bash completion --------------------------------------------------------
if [ -f /etc/bash/bash_completion.sh ]; then
    . /etc/bash/bash_completion.sh
elif [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
fi

# --- User overrides (persistent) -------------------------------------------
# Drop your own aliases, exports, functions, PS1 tweaks, etc. in
# /config/bashrc.local (host path: /addon_configs/opencode_terminal/bashrc.local)
# and they'll be sourced on every interactive shell.
if [ -f /config/bashrc.local ]; then
    . /config/bashrc.local
fi
