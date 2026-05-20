from __future__ import annotations

import argparse
from datetime import datetime, timezone
import importlib.util
from pathlib import Path
import sys
from typing import Optional

SRC_DIR = str(Path(__file__).resolve()).split("src")[0] + "src\\02_processing"
if str(SRC_DIR) not in sys.path:
    sys.path.append(str(SRC_DIR))

from common.db_connector import DbConnector
from silver_enriched.processing_pipeline.pipeline_utils import (
    LoadContext,
    finalize_pipeline_batch,
    start_pipeline_batch,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run processing pipeline steps (full or delta)."
    )
    parser.add_argument("--mode", choices=["full", "delta"], default="delta")
    parser.add_argument("--stage", default="processing", help="pipeline_batches.stage for watermark lookup")
    parser.add_argument("--watermark", default=None, help="ISO timestamp override for delta load")
    parser.add_argument("--batch-id", default=None, help="Optional batch UUID override")
    parser.add_argument(
        "--steps",
        default="text_summarizer",
        help="Comma-separated steps to run, or 'processing' for all steps",
    )
    parser.add_argument("--testing", action="store_true", help="Enable test run parameters")
    parser.add_argument(
        "--test-episode-id",
        type=str,
        default=None,
        help="Test run: episode id",
    )
    parser.add_argument(
        "--test-chapter-limit",
        type=int,
        default=3,
        help="Test run: max chapters",
    )
    parser.add_argument(
        "--test-end-watermark",
        default=None,
        help="Test run: upper bound watermark (ISO timestamp)",
    )
    return parser.parse_args()

def load_step_module(step_path: Path):
    module_name = step_path.stem.replace("-", "_")
    spec = importlib.util.spec_from_file_location(module_name, step_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Unable to load step module: {step_path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main() -> None:
    args = parse_args()
    steps = {step.strip() for step in args.steps.split(",") if step.strip()}
    print("steps to execute:", steps)
    
    connector = DbConnector()
    with connector.get_connection() as conn:
        stage = args.stage or "processing"
        load_mode = "full" if args.mode == "full" else "delta"
        batch_id = args.batch_id or start_pipeline_batch(conn, stage, load_mode)
        args.batch_id = batch_id
        processing_update_ts = datetime.now(timezone.utc)

        try:
            watermark = connector.parse_ts(args.watermark)
            if args.mode == "delta" and watermark is None:
                watermark = connector.get_watermark(conn, stage)

            ctx = LoadContext(
                mode=args.mode,
                watermark=watermark,
                connector=connector,
                processing_update_ts=processing_update_ts,
            )
            print("start watermark {} - end watermark: {} -  stage '{}': {}".format(watermark, args.test_end_watermark, stage, processing_update_ts))
            print("processing context (ctx):", ctx)

            base_dir = Path(__file__).resolve().parent
            step_map = {
                "text_summarizer": base_dir / "01_pipeline_text_summarizer.py",
            }

            if "processing" in steps:
                steps = set(step_map.keys())

            for step in steps:
                step_path = step_map.get(step)
                if step_path is None:
                    raise ValueError(f"Unknown step: {step}")

                module = load_step_module(step_path)
                if not hasattr(module, "run_step"):
                    raise RuntimeError(f"Step module missing run_step: {step_path}")
                print(f"------ Starting step: {step} ------")
                module.run_step(conn, ctx, args)
                print(f"------ Completed step: {step} ------")

            finalize_pipeline_batch(conn, batch_id, "success")
        except (KeyboardInterrupt, Exception):
            finalize_pipeline_batch(conn, batch_id, "failed")
            raise


if __name__ == "__main__":
    main()
