# computer specific zshrc settings

export WORKSPACE_DIR="${HOME}/Documents/archives/workspace"
alias cdw='cd ${WORKSPACE_DIR}'

export DOTFILES_DIR="${WORKSPACE_DIR}/dotfiles"
alias cdd='cd ${DOTFILES_DIR}'
alias codedd='code ${DOTFILES_DIR}'

# obsidian markdown notes
export MARKDOWN_NOTES_DIR="$HOME/Documents/archives/docs/notes"
alias cdn="cd $MARKDOWN_NOTES_DIR"
alias on='open "obsidian://open?vault=notes"'

export PERSONAL_MARKDOWN_NOTES_DIR="$HOME/Documents/archives/docs/personal_markdown_notes"
alias cdpn="cd $PERSONAL_MARKDOWN_NOTES_DIR"
alias opn='open "obsidian://open?vault=personal_markdown_notes"'

function rgn() {
    rg -i $@ "${PERSONAL_MARKDOWN_NOTES_DIR}"
    rg -i $@ "${MARKDOWN_NOTES_DIR}"
}

# golang paths
export GOPATH=$WORKSPACE_DIR/go

if [[ -d "$WORKSPACE_DIR/go/bin" ]]; then
  export PATH="$WORKSPACE_DIR/go/bin:$PATH"
fi