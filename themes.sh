#!/bin/bash

# Emits the theme list the overlay renders, as JSON:
#   {"current":"<display name>","rows":[{"name":...,"preview":...},...]}
# A preview is the theme's own preview.<ext> when it ships one, else its first
# background image — the same order omarchy-theme-switcher uses.

set -euo pipefail

USER_THEMES_PATH="$HOME/.config/omarchy/themes"
OMARCHY_THEMES_PATH="${OMARCHY_PATH:-/usr/share/omarchy}/themes"

# Themes are installed from third-party repos, so treat their contents as
# untrusted input: everything below is bounded so a crafted theme cannot make
# the overlay decode an arbitrary file or hold an unbounded payload.
MAX_PREVIEW_BYTES=$((8 * 1024 * 1024))
MAX_PREVIEW_PATH=1024
MAX_THEMES=500
MAX_NAME_CHARS=128

# A preview must resolve *inside* the theme it belongs to. The theme directory
# itself may legitimately be a symlink (a dev checkout linked into place), but a
# symlink within one must not redirect the overlay at something else — a device
# node, a keypair, an unbounded log.
contained_in() {
  local candidate="$1" root="$2" real_candidate real_root

  real_candidate=$(realpath -e -- "$candidate" 2>/dev/null) || return 1
  real_root=$(realpath -e -- "$root" 2>/dev/null) || return 1

  [[ $real_candidate == "$real_root"/* ]]
}

usable_preview() {
  local candidate="$1" theme_path="$2"

  (( ${#candidate} <= MAX_PREVIEW_PATH )) || return 1
  contained_in "$candidate" "$theme_path"
}

find_preview() {
  local theme_path="$1" preview preview_name

  for preview_name in preview.png preview.jpg preview.jpeg preview.webp preview.gif preview.bmp; do
    while IFS= read -r preview; do
      if usable_preview "$preview" "$theme_path"; then
        printf '%s\n' "$preview"
        return 0
      fi
    done < <(find -H "$theme_path" -maxdepth 1 -type f -iname "$preview_name" \
      -size -"$MAX_PREVIEW_BYTES"c -print 2>/dev/null)
  done

  if [[ -d $theme_path/backgrounds ]]; then
    while IFS= read -r preview; do
      if usable_preview "$preview" "$theme_path"; then
        printf '%s\n' "$preview"
        return 0
      fi
    done < <(find -H "$theme_path/backgrounds" -maxdepth 1 -type f \
      \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.gif' -o -iname '*.bmp' -o -iname '*.webp' \) \
      -size -"$MAX_PREVIEW_BYTES"c -print 2>/dev/null | sort)
  fi

  return 0
}

# omarchy-theme-list prints display names; theme directories are their slugs.
theme_dir_for() {
  local slug
  slug=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')

  if [[ -d $USER_THEMES_PATH/$slug ]]; then
    printf '%s\n' "$USER_THEMES_PATH/$slug"
  elif [[ -d $OMARCHY_THEMES_PATH/$slug ]]; then
    printf '%s\n' "$OMARCHY_THEMES_PATH/$slug"
  fi
}

current_slug=$(cat "$HOME/.local/state/omarchy/current/theme.name" 2>/dev/null || true)
current=""

rows=""
count=0
while IFS= read -r name; do
  [[ -n $name ]] || continue

  if (( count >= MAX_THEMES )); then
    printf 'themes.sh: more than %d themes, listing the first %d\n' "$MAX_THEMES" "$MAX_THEMES" >&2
    break
  fi

  # Names are directory names. A control character in one would break the
  # tab/newline framing jq reads below, and an absurdly long one is not a theme.
  if [[ $name == *[[:cntrl:]]* ]] || (( ${#name} > MAX_NAME_CHARS )); then
    continue
  fi

  dir=$(theme_dir_for "$name")
  preview=""
  [[ -n $dir ]] && preview=$(find_preview "$dir")
  [[ ${dir##*/} == "$current_slug" ]] && current="$name"

  rows+="$name"$'\t'"$preview"$'\n'
  count=$((count + 1))
done < <(omarchy-theme-list)

printf '%s' "$rows" | jq -R -s --arg current "$current" '{
  current: $current,
  rows: (
    split("\n")
    | map(select(length > 0) | split("\t") | { name: .[0], preview: (.[1] // "") })
  )
}'
