from __future__ import annotations

import argparse
import copy
import importlib.util
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import replace
from pathlib import Path

SRC_DIR = str(Path(__file__).resolve()).split("src")[0] + "src\\02_processing"
if str(SRC_DIR) not in sys.path:
    sys.path.append(str(SRC_DIR))

from common.app_logger import child_logger
from common.db_connector import DbConnector
from silver_enriched.processing_pipeline.pipeline_utils import (
    LoadContext, build_pipeline_logger, fetch_db_now, load_json_config)

# Steps that touch disjoint source/target tables and can run concurrently.
# embedder is intentionally excluded: it depends on text_summarizer's output.
PARALLEL_STEPS = ("text_summarizer", "fact_checker", "emotion_scoring")


def parse_args() -> argparse.Namespace:
    pre_parser = argparse.ArgumentParser(add_help=False)
    pre_parser.add_argument("--config", default=None, help="Path to pipeline args JSON config")
    pre_args, remaining = pre_parser.parse_known_args()

    parser = argparse.ArgumentParser(description="Run processing pipeline steps (full or delta).")
    parser.add_argument("--config", default="processing_pipeline_config.json", help="Path to pipeline args JSON config")
    parser.add_argument("--mode", choices=["full", "delta"], default="delta")
    parser.add_argument("--batch-id", default=None, help="Optional batch UUID override")
    parser.add_argument(
        "--max-workers",
        type=int,
        default=None,
        help="Max concurrent stage threads (default: one per parallel step)",
    )
    parser.add_argument(
        "--dry-run",
        action=argparse.BooleanOptionalAction,
        default=False,
        help="Run without writing database updates or creating pipeline batches",
    )
    parser.add_argument(
        "--steps",
        default="text_summarizer,fact_checker,embedder,emotion_scoring",
        help="Comma-separated steps to run, or 'processing' for all steps",
    )
    parser.add_argument("--testing", action="store_true", help="Enable test run parameters")
    parser.add_argument("--test-episode-id", type=str, default=None, help="Test run: episode id")
    parser.add_argument("--test-chapter-limit", type=int, default=3, help="Test run: max chapters")
    parser.add_argument(
        "--test-end-watermark",
        default=None,
        help="Test run: upper bound watermark (ISO timestamp)",
    )
    parser.add_argument(
        "--log-enabled",
        action=argparse.BooleanOptionalAction,
        default=False,
        help="Enable pipeline logging",
    )
    parser.add_argument("--log-level", default="INFO", help="Pipeline logger level")
    parser.add_argument("--log-dir", default="../logs", help="Optional pipeline log directory")
    parser.add_argument("--log-file", default="processing_pipeline.log", help="Pipeline log file name")

    config = load_json_config(pre_args.config or parser.get_default("config"), base_dir=Path(__file__).resolve().parent)
    if config:
        parser.set_defaults(**config)

    return parser.parse_args(remaining)


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
    steps = [step.strip() for step in args.steps.split(",") if step.strip()]

    if args.log_dir and not Path(args.log_dir).is_absolute():
        args.log_dir = str((Path(__file__).resolve().parent / args.log_dir).resolve())

    logger = build_pipeline_logger(
        module_name="processing_pipeline_runner",
        enabled=args.log_enabled,
        level=args.log_level,
        log_dir=args.log_dir,
        log_file=args.log_file,
    )
    logger.info(
        "pipeline: start mode=%s dry_run=%s steps=%s batch_id=%s workers=%s",
        args.mode,
        args.dry_run,
        ",".join(sorted(steps)),
        args.batch_id or "-",
        args.max_workers or "-",
    )

    connector = DbConnector()
    with connector.get_connection(logger=logger) as conn:
        new_processing_update_ts = fetch_db_now(conn)

    ctx = LoadContext(
        mode=args.mode,
        connector=connector,
        processing_update_ts=new_processing_update_ts,
        logger=logger,
        dry_run=args.dry_run,
    )

    base_dir = Path(__file__).resolve().parent
    step_map = {
        "text_summarizer": base_dir / "01_pipeline_text_summarizer.py",
        "fact_checker": base_dir / "02_pipeline_fact_checker.py",
        "embedder": base_dir / "03_pipeline_embedder.py",
        "emotion_scoring": base_dir / "04_pipeline_emotion_scoring.py",
    }

    if "processing" in steps:
        steps = list(step_map.keys())


    modules = {}
    for step in steps:
        step_path = step_map.get(step)
        if step_path is None:
            raise ValueError(f"Unknown step: {step}")
        module = load_step_module(step_path)
        if not hasattr(module, "run_step"):
            raise RuntimeError(f"Step module missing run_step: {step_path}")
        modules[step] = module

    def run_one(step: str) -> None:
        step_args = copy.copy(args)
        step_args.stage = step  # pipeline_batches.stage enum value matches the step name
        step_ctx = replace(ctx, logger=child_logger(logger, step))
        with connector.get_connection(logger=logger) as conn:
            logger.info("step: start %s", step)
            modules[step].run_step(conn, step_ctx, step_args)
            logger.info("step: done %s", step)

    parallel_steps = [s for s in steps if s in PARALLEL_STEPS]
    run_embedder = "embedder" in steps
    pool_size = args.max_workers or max(1, len(parallel_steps) + (1 if run_embedder else 0))

    errors = []
    with ThreadPoolExecutor(max_workers=pool_size) as executor:
        futures = {executor.submit(run_one, step): step for step in parallel_steps}
        summarizer_future = next(
            (future for future, step in futures.items() if step == "text_summarizer"),
            None,
        )

        if run_embedder:
            def run_embedder_after_summary() -> None:
                if summarizer_future is not None:
                    try:
                        summarizer_future.result()
                    except Exception:
                        logger.error("embedder: skipped because text_summarizer failed")
                        return
                run_one("embedder")

            futures[executor.submit(run_embedder_after_summary)] = "embedder"

        for future in as_completed(futures):
            step = futures[future]
            try:
                future.result()
            except (KeyboardInterrupt, Exception) as exc:
                errors.append((step, exc))
                logger.exception("pipeline: step failed %s", step)

    if errors:
        logger.error("pipeline: failed steps=%s", ", ".join(step for step, _ in errors))
        raise errors[0][1]

    logger.info("pipeline: done")


if __name__ == "__main__":
    main()