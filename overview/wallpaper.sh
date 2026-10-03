#!/bin/sh
# Prints the path of a still image of the current wallpaper.
# Works with Noctalia and DankMaterialShell; video wallpapers get one frame cached.
cache="${XDG_CACHE_HOME:-$HOME/.cache}/mango-overview"

if [ -n "$MANGO_OVERVIEW_WALLPAPER_CMD" ]; then
	wall=$(sh -c "$MANGO_OVERVIEW_WALLPAPER_CMD" 2>/dev/null)
else
	wall=$(timeout 1 noctalia msg wallpaper-get 2>/dev/null)
	[ -f "$wall" ] || wall=$(timeout 1 dms ipc call wallpaper get 2>/dev/null)
fi
wall=$(printf '%s' "$wall" | head -n1 | tr -d '"')

case "$wall" in
*.mp4 | *.webm | *.mkv | *.mov | *.avi | *.gif)
	mkdir -p "$cache"
	still="$cache/$(printf '%s' "$wall" | md5sum | cut -c1-16).jpg"
	[ -f "$still" ] || ffmpeg -loglevel error -y -ss 1 -i "$wall" -frames:v 1 -vf scale=1920:-2 "$still" </dev/null
	wall="$still"
	;;
esac

if [ -f "$wall" ]; then
	echo "$wall"
elif [ -f /var/lib/sddm-wallpaper/current.jpg ]; then
	echo /var/lib/sddm-wallpaper/current.jpg
fi
