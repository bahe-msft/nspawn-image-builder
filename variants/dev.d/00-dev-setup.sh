#!/bin/bash
set -euo pipefail

echo "[customize] Setting up development environment"

# Global git defaults
cat > /etc/gitconfig <<'EOF'
[init]
    defaultBranch = main
[pull]
    rebase = false
[color]
    ui = auto
[alias]
    st = status
    co = checkout
    br = branch
    ci = commit
    lg = log --oneline --graph --decorate
EOF

# Dev profile with useful aliases and helpers
cat > /etc/profile.d/dev.sh <<'PROFILE'
export EDITOR=vim
export VISUAL=vim

alias ll='ls -lah'
alias ..='cd ..'
alias ...='cd ../..'
alias grep='grep --color=auto'
alias py='python3'

# Quick venv creation
mkvenv() {
    python3 -m venv "${1:-.venv}"
    echo "Activate with: source ${1:-.venv}/bin/activate"
}
PROFILE
chmod 644 /etc/profile.d/dev.sh

# Set python3 as default python
update-alternatives --install /usr/bin/python python /usr/bin/python3 1 2>/dev/null || true

# Create workspace directory
mkdir -p /workspace
chmod 755 /workspace

touch /etc/nspawn-customized
echo "[customize] Development environment setup complete"
