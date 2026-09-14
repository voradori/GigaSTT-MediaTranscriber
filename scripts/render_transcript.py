"""Render the user-facing transcript text from transcript.json."""
import json
import os
import sys
from pathlib import Path


def stamp(seconds):
    whole = max(0, int(seconds))
    return f"{whole // 60}:{whole % 60:02d}"


def render(transcript):
    names = transcript.get("speaker_names", {})
    if not isinstance(names, dict):
        raise ValueError("speaker_names must be a mapping")
    labels = {word.get("speaker") for segment in transcript["segments"]
              for word in segment.get("words", [])}
    for label, name in names.items():
        if label not in labels or not isinstance(name, str) or not name.strip() or "\n" in name:
            raise ValueError(f"invalid speaker name mapping for {label}")
    lines = []
    for segment in transcript["segments"]:
        speaker = segment.get("speaker")
        label = ""
        if speaker:
            name = names.get(speaker)
            label = f"[{speaker} — {name}] " if name else f"[{speaker}] "
        elif "diarization" in transcript:
            label = "[UNKNOWN] "
        lines.append(f"({stamp(segment['start'])}) {label}{segment['text']}")
    return "\n".join(lines) + "\n"


def main():
    if len(sys.argv) != 2:
        print("Usage: .venv\\Scripts\\python.exe scripts/render_transcript.py output/transcripts/.../transcript.json", file=sys.stderr)
        return 2
    path = Path(sys.argv[1]).resolve()
    root = Path(__file__).resolve().parents[1] / "output" / "transcripts"
    if not path.is_relative_to(root) or path.name != "transcript.json":
        print("Expected transcript.json inside output/transcripts/.", file=sys.stderr)
        return 2
    transcript = json.loads(path.read_text(encoding="utf-8"))
    text = render(transcript)
    target = path.with_suffix(".txt")
    temporary = target.with_suffix(".txt.tmp")
    temporary.write_text(text, encoding="utf-8")
    os.replace(temporary, target)
    print(f"Updated {target}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
