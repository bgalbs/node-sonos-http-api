#!/bin/bash
# General Sonos control commands
# Reads speaker aliases from external config file

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
API="http://localhost:5005"
SPEAKERS_FILE="$SCRIPT_DIR/speakers.conf"

# Defaults
COMMAND=""
TARGET="kitchen"
VALUE=""

usage() {
  echo "Usage: $0 COMMAND [VALUE] [OPTIONS]"
  echo ""
  echo "Commands:"
  echo "  volume LEVEL [SPEAKER]   Set volume (0-100)"
  echo "  volume +/-N [SPEAKER]    Adjust volume up/down"
  echo "  play [SPEAKER]           Resume playback"
  echo "  pause [SPEAKER]          Pause playback (use 'all' for pauseall)"
  echo "  stop [SPEAKER]           Stop playback"
  echo "  skip [SPEAKER]           Skip to next track"
  echo "  prev [SPEAKER]           Go to previous track"
  echo "  shuffle on|off           Set shuffle mode"
  echo "  repeat all|one|none      Set repeat mode"
  echo "  group PRESET             Apply a speaker preset (e.g., 'all')"
  echo "  ungroup [SPEAKER]        Remove speaker from group"
  echo "  say \"MESSAGE\" [SPEAKER]  Text-to-speech announcement"
  echo ""
  echo "Options:"
  echo "  -t, --target SPEAKER  Target speaker or alias (default: kitchen)"
  echo "  --speakers            List speaker aliases"
  echo "  -h, --help            Show this help message"
  echo ""
  echo "Examples:"
  echo "  $0 volume 15 all"
  echo "  $0 volume +5 kitchen"
  echo "  $0 pause all"
  echo "  $0 skip office"
  echo "  $0 play kitchen"
  echo "  $0 ungroup office"
  echo "  $0 group all"
  echo "  $0 say \"Dinner is ready\" all"
}

list_speakers() {
  echo "Speaker aliases:"
  echo ""
  while IFS='|' read -r alias room; do
    [[ "$alias" =~ ^#.*$ || -z "$alias" ]] && continue
    printf "  %-12s -> %s\n" "$alias" "$room"
  done < "$SPEAKERS_FILE"
}

resolve_speaker() {
  local input="$1"
  while IFS='|' read -r alias room; do
    [[ "$alias" =~ ^#.*$ || -z "$alias" ]] && continue
    if [[ "$alias" == "$input" ]]; then
      echo "$room"
      return 0
    fi
  done < "$SPEAKERS_FILE"
  echo "$input"
}

url_encode() {
  local string="$1"
  echo "$string" | sed 's/ /%20/g'
}

# Parse arguments - extract command and value first, then options
while [[ $# -gt 0 ]]; do
  case $1 in
    -t|--target)
      TARGET="$2"
      shift 2
      ;;
    --speakers)
      list_speakers
      exit 0
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      echo "Unknown option: $1"
      usage
      exit 1
      ;;
    *)
      if [[ -z "$COMMAND" ]]; then
        COMMAND="$1"
      elif [[ -z "$VALUE" ]]; then
        VALUE="$1"
      fi
      shift
      ;;
  esac
done

# Validate command
if [[ -z "$COMMAND" ]]; then
  echo "Error: Command is required"
  echo ""
  usage
  exit 1
fi

# Resolve speaker alias
RESOLVED=$(resolve_speaker "$TARGET")

# Check if target is a preset reference
if [[ "$RESOLVED" == __PRESET__:* ]]; then
  PRESET_NAME="${RESOLVED#__PRESET__:}"
  IS_PRESET=true
  ROOM="Kitchen"  # Use kitchen as coordinator
else
  IS_PRESET=false
  ROOM="$RESOLVED"
fi

ROOM_ENCODED=$(url_encode "$ROOM")

# Execute command
case $COMMAND in
  volume)
    if [[ -z "$VALUE" ]]; then
      echo "Error: Volume level required"
      exit 1
    fi
    if [[ "$IS_PRESET" == true ]]; then
      echo "Setting group volume to $VALUE..."
      curl -s "$API/$ROOM_ENCODED/groupVolume/$VALUE" > /dev/null
    else
      echo "Setting volume to $VALUE on $ROOM..."
      curl -s "$API/$ROOM_ENCODED/volume/$VALUE" > /dev/null
    fi
    ;;
  play)
    # Allow play SPEAKER as shorthand
    if [[ -n "$VALUE" ]]; then
      RESOLVED=$(resolve_speaker "$VALUE")
      ROOM="$RESOLVED"
      ROOM_ENCODED=$(url_encode "$ROOM")
    fi
    echo "Resuming playback on $ROOM..."
    curl -s "$API/$ROOM_ENCODED/play" > /dev/null
    ;;
  pause)
    # Allow pause SPEAKER as shorthand
    if [[ -n "$VALUE" ]]; then
      RESOLVED=$(resolve_speaker "$VALUE")
      if [[ "$RESOLVED" == __PRESET__:* ]]; then
        IS_PRESET=true
      else
        IS_PRESET=false
        ROOM="$RESOLVED"
        ROOM_ENCODED=$(url_encode "$ROOM")
      fi
    fi
    if [[ "$IS_PRESET" == true ]]; then
      echo "Pausing all speakers..."
      curl -s "$API/pauseall" > /dev/null
    else
      echo "Pausing $ROOM..."
      curl -s "$API/$ROOM_ENCODED/pause" > /dev/null
    fi
    ;;
  stop)
    # Allow stop SPEAKER as shorthand
    if [[ -n "$VALUE" ]]; then
      RESOLVED=$(resolve_speaker "$VALUE")
      ROOM="$RESOLVED"
      ROOM_ENCODED=$(url_encode "$ROOM")
    fi
    echo "Stopping $ROOM..."
    curl -s "$API/$ROOM_ENCODED/stop" > /dev/null
    ;;
  skip|next)
    # Allow skip SPEAKER as shorthand
    if [[ -n "$VALUE" ]]; then
      RESOLVED=$(resolve_speaker "$VALUE")
      ROOM="$RESOLVED"
      ROOM_ENCODED=$(url_encode "$ROOM")
    fi
    echo "Skipping to next track..."
    curl -s "$API/$ROOM_ENCODED/next" > /dev/null
    ;;
  prev|previous)
    # Allow prev SPEAKER as shorthand
    if [[ -n "$VALUE" ]]; then
      RESOLVED=$(resolve_speaker "$VALUE")
      ROOM="$RESOLVED"
      ROOM_ENCODED=$(url_encode "$ROOM")
    fi
    echo "Going to previous track..."
    curl -s "$API/$ROOM_ENCODED/previous" > /dev/null
    ;;
  shuffle)
    if [[ -z "$VALUE" ]]; then
      echo "Error: shuffle requires 'on' or 'off'"
      exit 1
    fi
    echo "Setting shuffle $VALUE..."
    curl -s "$API/$ROOM_ENCODED/shuffle/$VALUE" > /dev/null
    ;;
  repeat)
    if [[ -z "$VALUE" ]]; then
      echo "Error: repeat requires 'all', 'one', or 'none'"
      exit 1
    fi
    echo "Setting repeat $VALUE..."
    curl -s "$API/$ROOM_ENCODED/repeat/$VALUE" > /dev/null
    ;;
  group)
    if [[ -z "$VALUE" ]]; then
      echo "Error: group requires a preset name (e.g., 'all' or 'whole_home')"
      exit 1
    fi
    # Resolve the preset name
    PRESET_RESOLVED=$(resolve_speaker "$VALUE")
    if [[ "$PRESET_RESOLVED" == __PRESET__:* ]]; then
      PRESET_NAME="${PRESET_RESOLVED#__PRESET__:}"
    else
      PRESET_NAME="$VALUE"
    fi
    echo "Applying preset $PRESET_NAME..."
    curl -s "$API/preset/$PRESET_NAME" > /dev/null
    ;;
  ungroup)
    # Allow ungroup SPEAKER as shorthand for ungroup -t SPEAKER
    if [[ -n "$VALUE" ]]; then
      RESOLVED=$(resolve_speaker "$VALUE")
      ROOM="$RESOLVED"
      ROOM_ENCODED=$(url_encode "$ROOM")
    fi
    echo "Removing $ROOM from group..."
    curl -s "$API/$ROOM_ENCODED/leave" > /dev/null
    ;;
  say)
    if [[ -z "$VALUE" ]]; then
      echo "Error: say requires a message"
      exit 1
    fi
    MESSAGE_ENCODED=$(url_encode "$VALUE")
    if [[ "$IS_PRESET" == true ]]; then
      echo "Announcing on all speakers: $VALUE"
      curl -s "$API/sayall/$MESSAGE_ENCODED" > /dev/null
    else
      echo "Announcing on $ROOM: $VALUE"
      curl -s "$API/$ROOM_ENCODED/say/$MESSAGE_ENCODED" > /dev/null
    fi
    ;;
  *)
    echo "Error: Unknown command '$COMMAND'"
    usage
    exit 1
    ;;
esac

echo "Done!"
