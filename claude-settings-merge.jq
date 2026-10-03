# ABOUTME: Merges claude-settings-patch.json into ~/.claude/settings.json for the claude-settings recipes.
# ABOUTME: Hook entries that run something from $dir are dropped first, so hooks removed from the patch go away.

def from_dotfiles: any(.hooks[]?; (.command // "") | contains($dir));

(if .hooks then
  .hooks |= (map_values(map(select(from_dotfiles | not))) | with_entries(select(.value != [])))
  | if .hooks == {} then del(.hooks) else . end
else . end)
| . * $patch
