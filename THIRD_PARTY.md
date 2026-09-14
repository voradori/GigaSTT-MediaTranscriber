# Third-party software and models

This project uses external software, libraries and machine-learning models.

These components are not part of this project's own source code and remain subject to their respective licenses, notices and terms of use.

## GigaSTT

Used as the local speech-to-text engine.

Upstream project: https://github.com/ekhodzitsky/gigastt

License: MIT for the GigaSTT project itself.

GigaSTT also downloads speech-recognition and punctuation model assets. Their licenses and notices are maintained by the GigaSTT project and should be reviewed in the upstream repository.

This project is not affiliated with or endorsed by the GigaSTT authors.

## yt-dlp

Used to download audio from supported YouTube URLs and playlists.

Upstream project: https://github.com/yt-dlp/yt-dlp

The upstream yt-dlp project is distributed under the Unlicense.

Users are responsible for ensuring that downloading or processing media complies with applicable law, copyright restrictions and the terms of the relevant service.

## pyannote.audio

Used for optional speaker diarization.

Upstream project: https://github.com/pyannote/pyannote-audio

License: MIT.

## pyannote speaker-diarization-community-1

Optional pretrained speaker-diarization model used by this project.

Model: https://huggingface.co/pyannote/speaker-diarization-community-1

License: CC BY 4.0.

The model is distributed through Hugging Face as a gated model. Users must accept the model author's access conditions before downloading it.

The model is downloaded directly from its upstream provider and is not distributed as part of this repository.

## Hugging Face Hub

Used to authenticate with Hugging Face and download the optional pyannote model.

Project: https://github.com/huggingface/huggingface_hub

The package is installed separately and remains subject to its upstream license.

## PyTorch, torchaudio and TorchCodec

Used by the optional pyannote diarization pipeline.

Projects:

- https://github.com/pytorch/pytorch
- https://github.com/pytorch/audio
- https://github.com/pytorch/torchcodec

These packages are installed separately during diarization setup and remain subject to their respective upstream licenses.

## FFmpeg

Used for media handling, including audio extraction from supported video files and by parts of the diarization stack.

Project: https://ffmpeg.org/

Windows build provider used by `setup.cmd`: https://github.com/BtbN/FFmpeg-Builds

The base setup automatically downloads an LGPL shared Windows build into the local `tools/ffmpeg/` directory. The archive is fetched from the upstream build provider at installation time and is not stored in this repository.

FFmpeg remains subject to its own LGPL/GPL licensing terms depending on the build and enabled components.

## Node.js

Installed automatically by `setup.cmd` from the official Node.js distribution and used by yt-dlp as a JavaScript runtime when a site requires JavaScript-based extraction.

Project: https://nodejs.org/

Node.js is downloaded at installation time into the local `tools/` directory, is not stored in this repository and remains subject to its upstream license and notices.

## Transitive dependencies

Python packages and other transitive dependencies installed by the components above may have additional licenses and notices.

Their authoritative licensing information is provided by the respective upstream projects and installed packages.

## Project license

Any license covering the original source code in this repository does not replace or override licenses that apply to third-party software, libraries, models or media.
