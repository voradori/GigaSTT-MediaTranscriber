"""Download one YouTube selection and process only its audio files."""
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

for stream in (sys.stdout, sys.stderr):
    if hasattr(stream, "reconfigure"):
        stream.reconfigure(encoding="utf-8", errors="replace")

ROOT = Path(__file__).resolve().parents[1]
TEMPLATE = "input/%(playlist_title|YouTube videos)s/%(title).100B [%(id)s].%(ext)s"


def main():
    download_only = len(sys.argv) == 3 and sys.argv[1] == "--download-only"
    diarize = len(sys.argv) == 3 and sys.argv[1] == "--diarize"
    if len(sys.argv) != (3 if download_only or diarize else 2) or not sys.argv[-1].strip():
        print("Usage: youtube.cmd URL or youtube_dr.cmd URL", file=sys.stderr)
        return 2
    if diarize and (not (ROOT / "models" /
            "pyannote-speaker-diarization-community-1" / "config.yaml").is_file()):
        print("Diarization is not installed. Run setup-diarization.cmd first.", file=sys.stderr)
        return 2
    url = sys.argv[-1].strip()
    audio_format = "bestaudio[ext=webm]/bestaudio" if download_only else "bestaudio"
    js_runtime = ["--js-runtimes", "node"] if shutil.which("node") else []
    with tempfile.TemporaryDirectory(prefix="gigastt-youtube-") as temporary:
        manifest = Path(temporary) / "downloaded.txt"
        download = subprocess.run([sys.executable, "-m", "yt_dlp", "--yes-playlist", "--no-overwrites",
                                   *js_runtime,
                                   "--print-to-file", "after_move:filepath", str(manifest),
                                   "-f", audio_format, "-o", TEMPLATE, url], cwd=ROOT)
        if download.returncode:
            return download.returncode
        returned_paths = manifest.read_text(encoding="utf-8").splitlines() if manifest.is_file() else []
    input_root = ROOT / "input"
    sources = []
    for line in returned_paths:
        path = (ROOT / line.strip()).resolve()
        if path.is_file() and path.is_relative_to(input_root) and path not in sources:
            sources.append(path)
    if not sources:
        print("No downloaded audio paths returned for this URL.", file=sys.stderr)
        return 2
    selected = [str(path.relative_to(input_root)) for path in sources]
    print(f"Selected {len(selected)} audio file(s) from this URL.", flush=True)
    if download_only:
        return 0
    result = subprocess.run([sys.executable, str(ROOT / "scripts" / "transcribe.py"), *selected], cwd=ROOT)
    if result.returncode:
        return result.returncode
    if diarize:
        result = subprocess.run([sys.executable, str(ROOT / "scripts" / "diarize.py"),
                                 *selected], cwd=ROOT,
                                env={**os.environ, "PYANNOTE_METRICS_ENABLED": "0"})
        return result.returncode
    return 0


if __name__ == "__main__":
    sys.exit(main())
