{ pkgs, lib, ... }:

# Voice notes: record, transcribe offline, drop into Notesnook. Move anything
# you want to keep out of RAM before shutting down.
#
#   Super + Shift + R   start recording / stop and transcribe
#   transcribe FILE     transcribe any existing audio file (mp3, m4a, opus, wav, ...)
#
# Each note lands in $XDG_RUNTIME_DIR/Recordings (RAM, gone at power-off) as a pair:
#   2026-10-19_1432.mp3   the audio
#   2026-10-19_1432.txt   the transcript (also copied to the clipboard)
# Drag the audio into a Notesnook note and paste the transcript as its text.

let
  dir = "$XDG_RUNTIME_DIR/Recordings";   # RAM (/run/user/<uid>): gone at power-off
  format = "mp3";        # output format for recordings: mp3, opus, m4a, wav, flac
  model = "base.en";     # base.en is fast on this CPU; small.en is more accurate but ~3x slower
  modelDir = "$HOME/.local/share/whisper";

  deps = with pkgs; [ coreutils gnused ffmpeg whisper-cpp libnotify wl-clipboard pipewire procps util-linux ];

  # Transcribe any audio file. Writes FILE's name with .txt next to it.
  transcribe = pkgs.writeShellApplication {
    name = "transcribe";
    runtimeInputs = deps;
    text = ''
      in="''${1:?usage: transcribe AUDIO_FILE}"
      [ -f "$in" ] || { echo "transcribe: no such file: $in" >&2; exit 1; }
      out="''${in%.*}"

      mkdir -p "${modelDir}"
      m="${modelDir}/ggml-${model}.bin"
      if [ ! -f "$m" ]; then
        notify-send -a "Voice note" "Downloading speech model" "One-time, about 150 MB"
        (cd "${modelDir}" && whisper-cpp-download-ggml-model ${model})
      fi

      # whisper.cpp wants 16 kHz mono WAV; ffmpeg converts from any format.
      tmp=$(mktemp --suffix=.wav)
      trap 'rm -f "$tmp"' EXIT
      ffmpeg -nostdin -loglevel error -y -i "$in" -ar 16000 -ac 1 -c:a pcm_s16le "$tmp"

      whisper-cli -m "$m" -f "$tmp" -l en -nt -otxt -of "$out" >/dev/null 2>&1

      # Tidy whitespace: one paragraph, no leading spaces.
      tr -s ' \n' ' ' < "$out.txt" | sed 's/^ //; s/ $//' > "$out.txt.tmp" && mv "$out.txt.tmp" "$out.txt"
      echo "$out.txt"
    '';
  };

  # Runs after a recording stops: transcribe, copy, notify. Separate script
  # so the keybind returns immediately while this works in the background.
  finish = pkgs.writeShellApplication {
    name = "voice-note-finish";
    runtimeInputs = deps ++ [ transcribe ];
    text = ''
      if txt=$(transcribe "$1"); then
        wl-copy < "$txt"
        notify-send -a "Voice note" "Transcript ready, copied" "$(head -c 160 "$txt")…"
      else
        notify-send -u critical -a "Voice note" "Transcription failed" "$1"
      fi
    '';
  };

  # Toggle: first press starts recording, second press stops, saves and transcribes.
  voiceNote = pkgs.writeShellApplication {
    name = "voice-note";
    runtimeInputs = deps ++ [ finish ];
    text = ''
      fmt="${format}"
      state="''${XDG_RUNTIME_DIR:-/tmp}/voice-note"
      mkdir -p "$state" "${dir}"

      if [ -f "$state/pid" ] && kill -0 "$(cat "$state/pid")" 2>/dev/null; then
        # --- Stop ---
        pid=$(cat "$state/pid"); name=$(cat "$state/name")
        kill -INT "$pid"                      # lets pw-record finish the WAV cleanly
        while kill -0 "$pid" 2>/dev/null; do sleep 0.1; done
        rm -f "$state/pid"

        final="${dir}/$name.$fmt"
        if [ "$fmt" = wav ]; then
          mv "$state/$name.wav" "$final"
        else
          ffmpeg -nostdin -loglevel error -y -i "$state/$name.wav" "$final"
          rm -f "$state/$name.wav"
        fi

        notify-send -a "Voice note" "Saved, transcribing…" "$name.$fmt"
        setsid -f voice-note-finish "$final" >/dev/null 2>&1 </dev/null
      else
        # --- Start ---
        name=$(date +%Y-%m-%d_%H%M%S)
        echo "$name" > "$state/name"
        setsid -f pw-record --channels 1 "$state/$name.wav" >/dev/null 2>&1 </dev/null
        # Find the recorder's PID by its output file (wait up to 2 s for it).
        for _ in $(seq 20); do
          pgrep -n -f "$state/$name.wav" > "$state/pid" && break
          sleep 0.1
        done
        notify-send -a "Voice note" "Recording" "Super + Shift + R to stop"
      fi
    '';
  };

  # Waybar indicator, visible only while recording.
  voiceStatus = pkgs.writeShellApplication {
    name = "voice-note-status";
    runtimeInputs = with pkgs; [ coreutils ];
    text = ''
      state="''${XDG_RUNTIME_DIR:-/tmp}/voice-note"
      if [ -f "$state/pid" ] && kill -0 "$(cat "$state/pid")" 2>/dev/null; then
        echo '{"text": "● REC", "class": "recording", "tooltip": "Recording (Super + Shift + R to stop)"}'
      else
        echo '{"text": ""}'
      fi
    '';
  };
in
{
  home.packages = [ voiceNote transcribe voiceStatus pkgs.whisper-cpp ];
}
