from __future__ import annotations

import argparse
import json
from pathlib import Path

from fact_checker_config import FactCheckerConfig
from fact_checker_core import FactChecker


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run fact checking for transcript text.")
    parser.add_argument("--config", default="fact_checker_config.json", help="Path to config JSON")
    parser.add_argument("--transcript", default=None, help="Path to transcript text file")
    parser.add_argument("--output", default=None, help="Path to output JSON file")
    parser.add_argument("--indent", type=int, default=2, help="Output JSON indentation")
    return parser.parse_args()


def _resolve_path(base_dir: Path, value: str) -> Path:
    path = Path(value).expanduser()
    if not path.is_absolute():
        path = base_dir / path
    return path


def _read_transcript(path: Path) -> str:
    if not path.exists():
        raise FileNotFoundError(f"Transcript input file not found: {path}")
    return path.read_text(encoding="utf-8").strip()


def main() -> None:
    args = parse_args()
    base_dir = Path(__file__).resolve().parent

    config = FactCheckerConfig.from_file(args.config)
    checker = FactChecker(config=config)

    transcript_path = _resolve_path(base_dir, args.transcript or config.default_transcript_path)
    output_path = _resolve_path(base_dir, args.output or config.default_output_path)

    transcript = _read_transcript(transcript_path)
    result = checker.fact_check(transcript)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("w", encoding="utf-8") as f:
        json.dump(result, f, indent=args.indent, ensure_ascii=False)

    print(json.dumps(result, indent=args.indent, ensure_ascii=False))
    print(f"Saved output to: {output_path}")


if __name__ == "__main__":
    main()
