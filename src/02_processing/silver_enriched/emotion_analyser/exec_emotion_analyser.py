from __future__ import annotations

import argparse
from typing import Dict, List, Union

from emotion_analyser import EmotionAnalyser
from emotion_config import EmotionConfig


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Score emotion from WAV or M4A audio files")
    parser.add_argument("files", nargs="*", help="Paths to .wav or .m4a files")
    parser.add_argument("--config", default="./emotion_analyser_config.json", help="Path to config JSON")
    parser.add_argument("--cache-dir", default=None, help="Override Hugging Face cache directory")
    return parser


def main() -> None:
    args = _build_parser().parse_args()

    config = EmotionConfig.from_file(args.config)
    if args.cache_dir is not None:
        config.cache_dir = args.cache_dir

    scorer = EmotionAnalyser(config=config)

    files_to_score = args.files or config.test_files
    if not files_to_score:
        raise ValueError("No input files provided and no test_files configured in config.")

    results: List[Dict[str, Union[str, int, float]]] = []
    for file in files_to_score:
        try:
            result = scorer.score_audio(file)
            results.append(result)
            print(f"Result for {file}: {result}")
        except Exception as exc:
            print(f"Error processing {file}: {exc}")



if __name__ == "__main__":
    main()
    
