# computer specific zshrc settings

export DROPBOX_DIR="${HOME}/Library/CloudStorage/Dropbox"

export CODE_DIR="${DROPBOX_DIR}/code"
alias cdc='cd ${CODE_DIR}'

export DOTFILES_DIR="${CODE_DIR}/dotfiles"
alias cdd='cd ${DOTFILES_DIR}'
alias codedd='code ${DOTFILES_DIR}'


export DOCS_DIR="${DROPBOX_DIR}/docs"
# obsidian markdown notes
export MARKDOWN_NOTES_DIR="${DOCS_DIR}/notes"
alias cdn="cd $MARKDOWN_NOTES_DIR"
alias on='open "obsidian://open?vault=notes"'

export PERSONAL_MARKDOWN_NOTES_DIR="${DOCS_DIR}/personal_markdown_notes"
alias cdpn="cd $PERSONAL_MARKDOWN_NOTES_DIR"
alias opn='open "obsidian://open?vault=personal_markdown_notes"'

export CLIPPINGS_NOTES_DIR="${DOCS_DIR}/clippings"
alias cdcl="cd $CLIPPINGS_NOTES_DIR"
alias oc='open "obsidian://open?vault=clippings"'

function rgn() {
    rg -i $@ "${PERSONAL_MARKDOWN_NOTES_DIR}"
    rg -i $@ "${MARKDOWN_NOTES_DIR}"
}

function rgc() {
    rg -i $@ "${CLIPPINGS_NOTES_DIR}"
}

alias cdnci="cd ${CODE_DIR}/naleid-consulting/invoices"

# golang paths
export GOPATH="${CODE_DIR}/go"
if [[ -d "${GOPATH}" ]]; then
  mkdir -p "${GOPATH}"
fi


if [[ -d "${GOPATH}/bin" ]]; then
  export PATH="${GOPATH}/bin:$PATH"
fi