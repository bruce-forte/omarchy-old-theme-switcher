#!/bin/bash

# Emits the theme list the overlay renders, as JSON:
#   {"current":"<display name>","rows":[{"name":...,"preview":...},...]}
# A preview is the theme's own preview.<ext> when it ships one, else its first
# background image — the same order omarchy-theme-switcher uses.

set -euo pipefail

USER_THEMES_PATH="$HOME/.config/omarchy/themes"
OMARCHY_THEMES_PATH="${OMARCHY_PATH:-/usr/share/omarchy}/themes"

find_preview() {
  local theme_path="$1" preview preview_name

  for preview_name in preview.png preview.jpg preview.jpeg preview.webp preview.gif preview.bmp; do
    preview=$(find -L "$theme_path" -maxdepth 1 -type f -iname "$preview_name" -print -quit 2>/dev/null)
    if [[ -n $preview ]]; then
      printf '%s\n' "$preview"
      return
    fi
  done

  if [[ -d $theme_path/backgrounds ]]; then
    find -L "$theme_path/backgrounds" -maxdepth 1 -type f \
      \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.gif' -o -iname '*.bmp' -o -iname '*.webp' \) \
      -print 2>/dev/null | sort | head -n 1
  fi
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
while IFS= read -r name; do
  [[ -n $name ]] || continue

  dir=$(theme_dir_for "$name")
  preview=""
  [[ -n $dir ]] && preview=$(find_preview "$dir")
  [[ ${dir##*/} == "$current_slug" ]] && current="$name"

  rows+="$name"$'\t'"$preview"$'\n'
done < <(omarchy-theme-list)

printf '%s' "$rows" | jq -R -s --arg current "$current" '{
  current: $current,
  rows: (
    split("\n")
    | map(select(length > 0) | split("\t") | { name: .[0], preview: (.[1] // "") })
  )
}'
