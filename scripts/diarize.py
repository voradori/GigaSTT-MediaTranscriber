"""Add local pyannote speaker labels to existing GigaSTT transcripts."""
import argparse
import copy
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path


for stream in (sys.stdout, sys.stderr):
    if hasattr(stream, "reconfigure"):
        stream.reconfigure(encoding="utf-8", errors="replace")


def ffmpeg_bin_directory():
    executable = shutil.which("ffmpeg")
    if executable:
        return Path(executable).parent
    local_app_data = os.environ.get("LOCALAPPDATA")
    if local_app_data:
        winget = Path(local_app_data) / "Microsoft" / "WinGet" / "Packages"
        matches = sorted(
            winget.glob("Gyan.FFmpeg.Shared_*/ffmpeg-*/bin/ffmpeg.exe"),
            reverse=True,
        )
        if matches:
            return matches[0].parent
    return None


# TorchCodec loads FFmpeg DLLs while pyannote is being imported.  On Windows,
# the WinGet installation directory may not reach a newly opened PowerShell yet.
FFMPEG_BIN = ffmpeg_bin_directory()
FFMPEG_DLL_DIRECTORY = None
if FFMPEG_BIN:
    os.environ["PATH"] = str(FFMPEG_BIN) + os.pathsep + os.environ.get("PATH", "")
    if os.name == "nt":
        FFMPEG_DLL_DIRECTORY = os.add_dll_directory(str(FFMPEG_BIN))

import torch
from pyannote.audio import Pipeline
from pyannote.audio.pipelines.utils.hook import ProgressHook


ROOT = Path(__file__).resolve().parents[1]
INPUT = ROOT / "input"
OUTPUT = ROOT / "output"
MODEL = ROOT / "models" / "pyannote-speaker-diarization-community-1"
MODEL_NAME = "pyannote/speaker-diarization-community-1"
YOUTUBE_ID = re.compile(r"\[([A-Za-z0-9_-]{11})\]")
RESULT_NAMES = (
    "diarization.json",
    "transcript.speakers.json",
    "transcript.speakers.txt",
)


def media_tool(name):
    executable = shutil.which(name)
    if executable:
        return executable
    raise RuntimeError(f"{name} is not installed or cannot be found")


def stamp(seconds):
    whole = max(0, int(seconds))
    return f"{whole // 60}:{whole % 60:02d}"


def write_json(path, value):
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(
        json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    os.replace(temporary, path)


def write_text(path, value):
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(value, encoding="utf-8")
    os.replace(temporary, path)


def media_duration(path):
    result = subprocess.run(
        [
            media_tool("ffprobe"),
            "-v",
            "error",
            "-show_entries",
            "format=duration",
            "-of",
            "default=nw=1:nk=1",
            str(path),
        ],
        check=True,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    return float(result.stdout.strip())


def prepare_audio(source, temporary):
    subprocess.run(
        [
            media_tool("ffmpeg"),
            "-nostdin",
            "-hide_banner",
            "-loglevel",
            "error",
            "-i",
            str(source),
            "-map",
            "0:a:0",
            "-ar",
            "16000",
            "-ac",
            "1",
            "-c:a",
            "pcm_s16le",
            "-y",
            str(temporary),
        ],
        check=True,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )


def youtube_id(path):
    match = YOUTUBE_ID.search(path.name)
    return match.group(1) if match else None


def find_audio(transcript_path):
    source = json.loads(transcript_path.read_text(encoding="utf-8")).get("source")
    wanted_id = youtube_id(transcript_path.parent)
    candidates = [path for path in INPUT.rglob("*") if path.is_file()]
    if wanted_id:
        matches = [path for path in candidates if wanted_id in path.name]
    else:
        matches = [path for path in candidates if path.name == source]
    if len(matches) != 1:
        raise RuntimeError(
            f"expected one matching audio file for {transcript_path.parent.name}, "
            f"found {len(matches)}"
        )
    return matches[0]


def best_speaker(start, end, turns):
    if end <= start:
        start -= 0.05
        end += 0.05
    best_label = None
    best_overlap = 0.0
    for turn in turns:
        if turn["end"] <= start:
            continue
        if turn["start"] >= end:
            break
        overlap = min(end, turn["end"]) - max(start, turn["start"])
        if overlap > best_overlap:
            best_overlap = overlap
            best_label = turn["speaker"]
    return best_label


def add_speakers(transcript, turns):
    labeled_segments = []
    for segment in transcript.get("segments", []):
        words = segment.get("words", [])
        rendered = segment.get("text", "").split()
        if len(rendered) != len(words):
            rendered = [word.get("word", "") for word in words]
        labeled = []
        for token, original_word in zip(rendered, words):
            word = copy.deepcopy(original_word)
            speaker = best_speaker(float(word["start"]), float(word["end"]), turns)
            word["speaker"] = speaker
            labeled.append((token, word))
        labeled_segments.append(labeled)

    flat_words = [word for segment in labeled_segments for _, word in segment]
    index = 0
    while index < len(flat_words):
        if flat_words[index]["speaker"] is not None:
            index += 1
            continue
        start = index
        while index < len(flat_words) and flat_words[index]["speaker"] is None:
            index += 1
        previous = flat_words[start - 1] if start else None
        following = flat_words[index] if index < len(flat_words) else None
        if (
            previous
            and following
            and previous["speaker"] == following["speaker"]
            and float(following["start"]) - float(previous["end"]) <= 2.0
        ):
            for word in flat_words[start:index]:
                word["speaker"] = previous["speaker"]

    enriched_segments = []
    for labeled in labeled_segments:
        group = []
        group_speaker = None
        for token, word in labeled:
            speaker = word["speaker"]
            if group and speaker != group_speaker:
                enriched_segments.append(make_segment(group, group_speaker))
                group = []
            if not group:
                group_speaker = speaker
            group.append((token, word))
        if group:
            enriched_segments.append(make_segment(group, group_speaker))
    assigned = sum(word["speaker"] is not None for word in flat_words)
    total = len(flat_words)
    result = copy.deepcopy(transcript)
    result["segments"] = enriched_segments
    result["diarization"] = {
        "model": MODEL_NAME,
        "method": "exclusive speaker diarization; maximum overlap per word",
        "assigned_words": assigned,
        "total_words": total,
    }
    return result


def make_segment(group, speaker):
    return {
        "start": group[0][1]["start"],
        "end": group[-1][1]["end"],
        "speaker": speaker,
        "text": " ".join(token for token, _ in group),
        "words": [word for _, word in group],
    }


def readable_text(transcript):
    lines = []
    for segment in transcript["segments"]:
        speaker = segment.get("speaker") or "UNKNOWN"
        lines.append(f"({stamp(segment['start'])}) [{speaker}] {segment['text']}")
    return "\n".join(lines) + "\n"


def valid_existing(target):
    if not all((target / name).is_file() for name in RESULT_NAMES):
        return False
    try:
        diarization = json.loads((target / RESULT_NAMES[0]).read_text(encoding="utf-8"))
        transcript = json.loads((target / RESULT_NAMES[1]).read_text(encoding="utf-8"))
        return isinstance(diarization.get("exclusive_diarization"), list) and isinstance(
            transcript.get("segments"), list
        )
    except (OSError, ValueError, AttributeError):
        raise RuntimeError(f"existing speaker results need inspection: {target}")


def process(pipeline, device, transcript_path, force=False, rerun_model=False):
    target = transcript_path.parent
    if not force and valid_existing(target):
        print(f"SKIP existing: {target}", flush=True)
        return
    transcript = json.loads(transcript_path.read_text(encoding="utf-8"))
    audio = find_audio(transcript_path)
    audio_seconds = media_duration(audio)
    transcript_seconds = float(transcript.get("duration") or 0.0)
    difference = abs(audio_seconds - transcript_seconds)
    if difference > 1.0:
        raise RuntimeError(
            f"audio/transcript duration mismatch for {audio.name}: {difference:.3f}s"
        )
    diarization_path = target / RESULT_NAMES[0]
    if diarization_path.is_file() and not rerun_model:
        diarization = json.loads(diarization_path.read_text(encoding="utf-8"))
        turns = diarization["exclusive_diarization"]
        print(f"REUSE diarization: {diarization_path}", flush=True)
    else:
        if pipeline is None:
            raise RuntimeError("pyannote pipeline was not loaded")
        print(f"DIARIZE {audio.name} on {device}", flush=True)
        temporary_audio = target / "diarization-input.wav"
        try:
            prepare_audio(audio, temporary_audio)
            with ProgressHook() as hook:
                output = pipeline(str(temporary_audio), hook=hook)
        finally:
            temporary_audio.unlink(missing_ok=True)
        serialized = output.serialize()
        turns = serialized["exclusive_diarization"]
        diarization = {
            "source": audio.name,
            "audio_duration": audio_seconds,
            "transcript_duration": transcript_seconds,
            "model": MODEL_NAME,
            "device": device,
            **serialized,
        }
        write_json(diarization_path, diarization)
    enriched = add_speakers(transcript, turns)
    write_json(target / RESULT_NAMES[1], enriched)
    write_text(target / RESULT_NAMES[2], readable_text(enriched))
    stats = enriched["diarization"]
    speakers = sorted({turn["speaker"] for turn in turns})
    print(
        f"DONE {audio.name}: {len(speakers)} speakers, "
        f"{stats['assigned_words']}/{stats['total_words']} words assigned",
        flush=True,
    )


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--id", help="process only the result containing this YouTube ID")
    parser.add_argument("--force", action="store_true", help="replace speaker result files")
    parser.add_argument(
        "--rerun-model", action="store_true", help="run pyannote again instead of reusing diarization.json"
    )
    args = parser.parse_args()
    if not MODEL.joinpath("config.yaml").is_file():
        print("Community-1 is not installed in models/.", file=sys.stderr)
        return 2
    transcripts = [
        path
        for path in OUTPUT.rglob("transcript.json")
        if not args.id or args.id in str(path.parent)
    ]
    if not transcripts:
        print("No matching transcript.json files found.", file=sys.stderr)
        return 2
    device = "cuda" if torch.cuda.is_available() else "cpu"
    needs_pipeline = args.rerun_model or any(
        not path.parent.joinpath(RESULT_NAMES[0]).is_file() for path in transcripts
    )
    pipeline = None
    if needs_pipeline:
        pipeline = Pipeline.from_pretrained(str(MODEL))
        pipeline.to(torch.device(device))
    failures = []
    for transcript_path in sorted(transcripts):
        try:
            process(
                pipeline,
                device,
                transcript_path,
                force=args.force,
                rerun_model=args.rerun_model,
            )
        except (
            OSError,
            ValueError,
            KeyError,
            TypeError,
            RuntimeError,
            subprocess.CalledProcessError,
        ) as error:
            failures.append((transcript_path.parent.name, str(error)))
            print(f"FAILED {transcript_path.parent.name}: {error}", file=sys.stderr)
    if failures:
        print(
            f"Finished with {len(failures)} failure(s) out of {len(transcripts)} file(s):",
            file=sys.stderr,
        )
        for name, error in failures:
            print(f"- {name}: {error}", file=sys.stderr)
        return 1
    print(f"Finished successfully: {len(transcripts)} file(s).", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
