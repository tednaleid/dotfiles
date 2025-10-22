# cardinal uses the same config as starling

local aliasfile="${HOME}/.zsh.d/starling.sh"
if [[ -e ${aliasfile} ]]; then
    source ${aliasfile}
else
    echo "Unable to find ${aliasfile}"
fi