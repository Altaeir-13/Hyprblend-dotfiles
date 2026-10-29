# Use user local bin
case ":$PATH:" in
    *":${XDG_BIN_HOME:-$HOME/.local/bin}:"*) ;;
    *) export PATH="${XDG_BIN_HOME:-$HOME/.local/bin}:$PATH" ;;
esac

# Use the generated color scheme

if test -f ~/.local/state/quickshell/user/generated/terminal/sequences.txt; then
    cat ~/.local/state/quickshell/user/generated/terminal/sequences.txt
fi
