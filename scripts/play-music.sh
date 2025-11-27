#!/bin/bash
# Play music on Sonos speakers
# Reads playlists and speaker aliases from external config files

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
API="http://localhost:5005"
PLAYLISTS_FILE="$SCRIPT_DIR/playlists.conf"
SPEAKERS_FILE="$SCRIPT_DIR/speakers.conf"

# Defaults
PLAYLIST=""
TARGET=""
SHUFFLE=false
REPEAT=true

usage() {
  echo "Usage: $0 -p PLAYLIST [OPTIONS]"
  echo ""
  echo "Required:"
  echo "  -p, --playlist NAME   Playlist to play (see --list)"
  echo ""
  echo "Options:"
  echo "  -t, --target SPEAKER  Target speaker or alias (default: kitchen)"
  echo "                        Use 'all' for whole home"
  echo "  -s, --shuffle         Enable shuffle mode"
  echo "  --no-repeat           Disable repeat"
  echo "  -l, --list            List available playlists"
  echo "  --speakers            List speaker aliases"
  echo "  -h, --help            Show this help message"
}

list_playlists() {
  echo "Available playlists:"
  echo ""
  while IFS='|' read -r name uri desc; do
    [[ "$name" =~ ^#.*$ || -z "$name" ]] && continue
    printf "  %-12s %s\n" "$name" "$desc"
  done < "$PLAYLISTS_FILE"
}

list_speakers() {
  echo "Speaker aliases:"
  echo ""
  while IFS='|' read -r alias room; do
    [[ "$alias" =~ ^#.*$ || -z "$alias" ]] && continue
    printf "  %-12s -> %s\n" "$alias" "$room"
  done < "$SPEAKERS_FILE"
}

get_playlist_uri() {
  local name="$1"
  while IFS='|' read -r pname uri desc; do
    [[ "$pname" =~ ^#.*$ || -z "$pname" ]] && continue
    if [[ "$pname" == "$name" ]]; then
      echo "$uri"
      return 0
    fi
  done < "$PLAYLISTS_FILE"
  return 1
}

get_playlist_desc() {
  local name="$1"
  while IFS='|' read -r pname uri desc; do
    [[ "$pname" =~ ^#.*$ || -z "$pname" ]] && continue
    if [[ "$pname" == "$name" ]]; then
      echo "$desc"
      return 0
    fi
  done < "$PLAYLISTS_FILE"
  return 1
}

resolve_speaker() {
  local input="$1"
  # Check aliases file first
  while IFS='|' read -r alias room; do
    [[ "$alias" =~ ^#.*$ || -z "$alias" ]] && continue
    if [[ "$alias" == "$input" ]]; then
      echo "$room"
      return 0
    fi
  done < "$SPEAKERS_FILE"
  # Not found in aliases, return as-is (might be a room name)
  echo "$input"
}

url_encode() {
  local string="$1"
  echo "$string" | sed 's/ /%20/g'
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -p|--playlist)
      PLAYLIST="$2"
      shift 2
      ;;
    -t|--target)
      TARGET="$2"
      shift 2
      ;;
    -s|--shuffle)
      SHUFFLE=true
      shift
      ;;
    --no-repeat)
      REPEAT=false
      shift
      ;;
    -l|--list)
      list_playlists
      exit 0
      ;;
    --speakers)
      list_speakers
      exit 0
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      usage
      exit 1
      ;;
  esac
done

# Validate playlist is provided
if [[ -z "$PLAYLIST" ]]; then
  echo "Error: Playlist is required"
  echo ""
  usage
  exit 1
fi

# Validate playlist exists
SPOTIFY_URI=$(get_playlist_uri "$PLAYLIST")
if [[ -z "$SPOTIFY_URI" ]]; then
  echo "Error: Unknown playlist '$PLAYLIST'"
  echo "Use --list to see available playlists"
  exit 1
fi

PLAYLIST_DESC=$(get_playlist_desc "$PLAYLIST")

# Default target to kitchen if not specified
if [[ -z "$TARGET" ]]; then
  TARGET="kitchen"
fi

# Resolve speaker alias
RESOLVED=$(resolve_speaker "$TARGET")

# Check if it's a preset
if [[ "$RESOLVED" == __PRESET__:* ]]; then
  PRESET_NAME="${RESOLVED#__PRESET__:}"
  echo "Playing: $PLAYLIST_DESC"
  echo "Target: Whole home (preset: $PRESET_NAME)"

  # Apply preset first
  echo "Grouping speakers..."
  curl -s "$API/preset/$PRESET_NAME" > /dev/null
  sleep 2

  # Use kitchen as coordinator for grouped playback
  ROOM="Kitchen"
else
  ROOM="$RESOLVED"
  echo "Playing: $PLAYLIST_DESC"
  echo "Target: $ROOM"
fi

ROOM_ENCODED=$(url_encode "$ROOM")

# Play the music
echo "Starting music..."
curl -s "$API/$ROOM_ENCODED/spotify/now/$SPOTIFY_URI" > /dev/null

# Set repeat mode
if [ "$REPEAT" = true ]; then
  curl -s "$API/$ROOM_ENCODED/repeat/all" > /dev/null
else
  curl -s "$API/$ROOM_ENCODED/repeat/none" > /dev/null
fi

# Set shuffle mode
if [ "$SHUFFLE" = true ]; then
  echo "Shuffle: on"
  curl -s "$API/$ROOM_ENCODED/shuffle/on" > /dev/null
else
  curl -s "$API/$ROOM_ENCODED/shuffle/off" > /dev/null
fi

echo "Done!"
