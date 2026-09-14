"""Offline folder runner for the locally installed GigaSTT CLI."""
import json
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
INPUT = ROOT / "input"
OUTPUT = ROOT / "output"
ENGINE = ROOT / "tools" / "gigastt.exe"
MODELS = ROOT / "models"
FORMATS = {".ogg", ".opus", ".mp3", ".wav", ".m4a", ".flac", ".webm"}
VIDEO = {".mp4"}


def stamp(seconds):
    whole = max(0, int(seconds))
    return f"{whole // 60}:{whole % 60:02d}"


def normalize(raw, source):
    words = raw.get("words", [])
    rendered = []
    for token in raw.get("text", "").split():
        if re.sub(r"[^\w]", "", token, flags=re.UNICODE):
            rendered.append(token)
        elif rendered and token in {".", ",", "?", "!", ":", ";"}:
            rendered[-1] += token
    if len(rendered) != len(words) or any(
        re.sub(r"[^\w]", "", token, flags=re.UNICODE).casefold() !=
        re.sub(r"[^\w]", "", word.get("word", ""), flags=re.UNICODE).casefold()
        for token, word in zip(rendered, words)
    ):
        rendered = [word["word"] for word in words]
    segments = []
    current = []
    for index, word in enumerate(words):
        if current and (word["start"] - current[-1][1]["end"] > 0.9 or
                        word["end"] - current[0][1]["start"] > 10 or
                        len(current) >= 32 or
                        rendered[index - 1].endswith((".", "?", "!")) or
                        word.get("speaker") != current[-1][1].get("speaker")):
            segments.append(current)
            current = []
        current.append((index, word))
    if current:
        segments.append(current)
    result = []
    for group in segments:
        first, last = group[0][1], group[-1][1]
        result.append({"start": first["start"], "end": last["end"],
                       "speaker": first.get("speaker"),
                       "text": " ".join(rendered[i] for i, _ in group),
                       "words": [word for _, word in group]})
    return {"source": source, "duration": raw.get("duration"),
            "text": raw.get("text", ""), "segments": result}


def process(source):
    target = OUTPUT / source.name
    if all((target / name).is_file() for name in ("raw.json", "transcript.json", "transcript.txt")):
        print(f"SKIP existing: {target}", flush=True)
        return True
    target.mkdir(parents=True)
    raw_file = target / "raw.json"
    started = time.monotonic()
    audio_source = source
    temporary_audio = target / "extracting.m4a"
    if source.suffix.lower() in VIDEO:
        if not shutil.which("ffmpeg"):
            print(f"FAILED {source.name}: ffmpeg is unavailable", file=sys.stderr)
            return False
        try:
            subprocess.run(["ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error",
                            "-i", str(source), "-map", "0:a:0", "-vn", "-c:a", "copy",
                            "-y", str(temporary_audio)], check=True)
            audio_source = temporary_audio
        except subprocess.CalledProcessError as error:
            print(f"FAILED {source.name}: audio extraction failed: {error}", file=sys.stderr)
            return False
    command = [str(ENGINE), "--offline", "--log-level", "warn", "transcribe", "--model-dir", str(MODELS),
               "--punctuation", "on", "--punct-model-dir", str(MODELS / "punct"),
               "--itn", "off", "-f", "json", "-o",
               str(raw_file), str(audio_source)]
    print(f"PROCESS {source.name}", flush=True)
    try:
        environment = os.environ.copy()
        environment.setdefault("RUST_LOG", "warn")
        subprocess.run(command, check=True, env=environment)
        raw = json.loads(raw_file.read_text(encoding="utf-8"))
        if not isinstance(raw.get("words"), list):
            raise ValueError("GigaSTT JSON has no words array")
        transcript = normalize(raw, source.name)
        (target / "transcript.json").write_text(
            json.dumps(transcript, ensure_ascii=False, indent=2), encoding="utf-8")
        lines = [f"({stamp(s['start'])}) " +
                 (f"[{s['speaker']}] " if s["speaker"] else "") + s["text"]
                 for s in transcript["segments"]]
        (target / "transcript.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")
        if temporary_audio.exists():
            temporary_audio.unlink()
        print(f"DONE {source.name}: {len(lines)} lines, {time.monotonic()-started:.1f}s", flush=True)
        return True
    except (subprocess.CalledProcessError, ValueError, KeyError, OSError) as error:
        (target / "error.txt").write_text(str(error), encoding="utf-8")
        print(f"FAILED {source.name}: {error}", file=sys.stderr, flush=True)
        return False


def main():
    if not ENGINE.is_file() or not (MODELS / "punct" / "rupunct_small_int8.onnx").is_file():
        print("GigaSTT is not installed. Run setup.cmd once online.", file=sys.stderr)
        return 2
    INPUT.mkdir(exist_ok=True)
    OUTPUT.mkdir(exist_ok=True)
    sources = sorted(p for p in INPUT.iterdir() if p.is_file() and p.suffix.lower() in FORMATS | VIDEO)
    if not sources:
        print("No supported audio files in input/.")
        return 0
    outcomes = [process(source) for source in sources]
    return 0 if all(outcomes) else 1


if __name__ == "__main__":
    sys.exit(main())
