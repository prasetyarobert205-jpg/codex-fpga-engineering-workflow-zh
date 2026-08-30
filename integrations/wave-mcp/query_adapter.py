#!/usr/bin/env python3
"""wave-mcp 公开 API 的最小 point + bounded range 诊断适配层。

本文件不包含 Tencent/wave-mcp 源码，只调用其公开 Python API。
输出只能作为 OBSERVATION_ONLY / DIAGNOSTIC_ONLY 证据。
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.metadata
import json
import os
from pathlib import Path
from typing import Any


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def write_json_exclusive(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, "w", encoding="utf-8", newline="\n") as handle:
        json.dump(value, handle, indent=2, sort_keys=True)
        handle.write("\n")


def load_session_manifest(path: Path) -> tuple[Path, dict[str, Any]]:
    manifest = path / "session.json" if path.is_dir() else path
    data = json.loads(manifest.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError("session.json 顶层必须是 object")
    return manifest, data


def _valid_four_state(value: Any, width: int) -> bool:
    return (
        isinstance(value, str)
        and len(value) == width
        and all(char in "01xXzZ" for char in value)
    )


def normalize_window_start(
    point: Any, values: Any, width: Any
) -> tuple[list[dict[str, Any]] | None, dict[str, Any], str | None]:
    """Validate point(start), range ordering, and same-timestamp semantics.

    wave-mcp 0.1.1 defines point as the last change at or before start and
    range as changes within the inclusive interval.  The normalized sequence
    therefore keeps the settled point value at start, removes all raw range
    events at that same timestamp, and appends later transitions.
    """
    boundary = {
        "policy": "POINT_SETTLED_AT_START; RANGE_INCLUSIVE; LAST_SAME_TIME_RANGE_MUST_MATCH_POINT",
        "consistent": False,
    }
    if not isinstance(width, int) or isinstance(width, bool) or width < 1:
        return None, boundary, "SIGNAL_WIDTH_INVALID"
    if not isinstance(point, dict):
        return None, boundary, "POINT_RESULT_INVALID"
    point_value = point.get("value")
    point_time = point.get("time_units")
    if not _valid_four_state(point_value, width) or not isinstance(point_time, int):
        return None, boundary, "POINT_VALUE_INVALID"
    if not isinstance(values, list):
        return None, boundary, "BACKEND_PROTOCOL_MISMATCH"

    previous_time = point_time
    same_time_values: list[str] = []
    later: list[dict[str, Any]] = []
    for item in values:
        if not isinstance(item, dict):
            return None, boundary, "BACKEND_PROTOCOL_MISMATCH"
        item_time = item.get("time_units")
        item_value = item.get("value")
        if (
            not isinstance(item_time, int)
            or item_time < point_time
            or item_time < previous_time
            or not _valid_four_state(item_value, width)
        ):
            return None, boundary, "BACKEND_PROTOCOL_MISMATCH"
        previous_time = item_time
        if item_time == point_time:
            same_time_values.append(item_value)
        else:
            normalized = dict(item)
            normalized["source"] = "range_transition"
            later.append(normalized)

    if same_time_values and same_time_values[-1] != point_value:
        return None, boundary, "WINDOW_START_SEMANTICS_AMBIGUOUS"
    boundary["consistent"] = True
    boundary["same_timestamp_range_events"] = len(same_time_values)
    start_item = dict(point)
    start_item["source"] = "point_at_start"
    return [start_item, *later], boundary, None


def bounded_range_values(ranged: Any, transition_cap: int) -> tuple[list[Any] | None, str | None]:
    if not isinstance(ranged, dict):
        return None, "BACKEND_PROTOCOL_MISMATCH"
    values = ranged.get("values")
    if not isinstance(values, list) or ranged.get("count") != len(values):
        return None, "BACKEND_PROTOCOL_MISMATCH"
    if len(values) == transition_cap + 1:
        return None, "QUERY_RESULT_TRUNCATED_OR_OVER_BUDGET"
    if len(values) > transition_cap + 1:
        return None, "BACKEND_PROTOCOL_MISMATCH"
    return values, None


def main() -> int:
    parser = argparse.ArgumentParser(description="执行 wave-mcp point(start) + C+1 range 诊断查询")
    parser.add_argument("--session", required=True, type=Path)
    parser.add_argument("--signal", required=True)
    parser.add_argument("--start-ps", required=True, type=int)
    parser.add_argument("--end-ps", required=True, type=int)
    parser.add_argument("--transition-cap", required=True, type=int)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()

    if not args.signal or len(args.signal) > 1024:
        parser.error("--signal 必须是有界非空层次路径")
    if args.start_ps < 0 or args.end_ps < args.start_ps:
        parser.error("时间窗口必须满足 0 <= start <= end")
    if args.transition_cap < 1:
        parser.error("--transition-cap 必须为正整数")
    session = args.session.resolve(strict=True)
    output = args.output.resolve(strict=False)
    if output.exists():
        parser.error(f"拒绝覆盖已有输出：{output}")

    session_manifest, session_data = load_session_manifest(session)
    fst_value = session_data.get("fst_path")
    if isinstance(fst_value, str) and fst_value:
        fst_candidate = Path(fst_value)
        if not fst_candidate.is_absolute():
            fst_candidate = session_manifest.parent / fst_candidate
        fst_path = fst_candidate.resolve(strict=True)
    else:
        fst_path = None
    session_id = "public-query-adapter"
    receipt: dict[str, Any] = {
        "schema_version": "public-wave-mcp-query-receipt-1.0",
        "claim_scope": "OBSERVATION_ONLY",
        "classification": "DIAGNOSTIC_ONLY",
        "status": "INCONCLUSIVE",
        "reason_code": None,
        "session_manifest_sha256": sha256_file(session_manifest),
        "session_declared_fst_fingerprint_sha1_first_mib": session_data.get("fst_hash"),
        "input_wave_sha256": sha256_file(fst_path) if fst_path else None,
        "input_wave_size": fst_path.stat().st_size if fst_path else None,
        "signal": args.signal,
        "start_ps": args.start_ps,
        "end_ps": args.end_ps,
        "requested_cap": args.transition_cap,
        "backend_limit": args.transition_cap + 1,
        "wave_mcp_version": None,
        "signal_width": None,
        "boundary": None,
        "point_result": None,
        "range_result": None,
        "normalized_values": None,
    }
    opened = False
    if fst_path is None:
        receipt["reason_code"] = "SESSION_HAS_NO_WAVEFORM"
    else:
        try:
            from wave_mcp import server

            receipt["wave_mcp_version"] = importlib.metadata.version("wave-mcp")
            result = server.open_session(str(session), session_id)
            opened = True
            if result.get("warnings"):
                receipt["reason_code"] = "SESSION_WARNING"
                receipt["detail"] = result["warnings"]
            else:
                info = server.signal_info(args.signal, session_id)
                if "error" in info:
                    receipt["reason_code"] = "SIGNAL_NOT_FOUND"
                    receipt["detail"] = info["error"]
                else:
                    receipt["signal_width"] = info.get("width")
                    point = server.signal_value_at(args.signal, f"{args.start_ps}ps", session_id)
                    ranged = server.signal_values_in_range(
                        args.signal,
                        f"{args.start_ps}ps",
                        f"{args.end_ps}ps",
                        args.transition_cap + 1,
                        session_id,
                    )
                    receipt["point_result"] = point
                    if "error" in point or "error" in ranged:
                        receipt["reason_code"] = "QUERY_FAILED"
                        receipt["detail"] = point.get("error") or ranged.get("error")
                    else:
                        values, range_reason = bounded_range_values(ranged, args.transition_cap)
                        if range_reason:
                            receipt["reason_code"] = range_reason
                            receipt["range_result"] = {"count": ranged.get("count")}
                        else:
                            receipt["range_result"] = {"count": len(values), "values": values}
                            normalized, boundary, reason = normalize_window_start(
                                point, values, receipt["signal_width"]
                            )
                            receipt["boundary"] = boundary
                            receipt["normalized_values"] = normalized
                            if reason:
                                receipt["reason_code"] = reason
                            else:
                                receipt["status"] = "COMPLETE"
        except Exception as exc:  # diagnostic adapter: preserve a typed failure receipt
            receipt["reason_code"] = receipt["reason_code"] or "TOOL_OR_ADAPTER_UNAVAILABLE"
            receipt["exception_type"] = type(exc).__name__
            receipt["detail"] = str(exc)
        finally:
            if opened:
                try:
                    receipt["session_close"] = server.close_session(session_id)
                except Exception as exc:  # the query result cannot be COMPLETE if close failed
                    receipt["status"] = "INCONCLUSIVE"
                    receipt["reason_code"] = "SESSION_CLOSE_FAILED"
                    receipt["close_exception_type"] = type(exc).__name__
                    receipt["close_detail"] = str(exc)
    write_json_exclusive(output, receipt)
    print(json.dumps(receipt, ensure_ascii=False, sort_keys=True))
    return 0 if receipt["status"] == "COMPLETE" else 2


if __name__ == "__main__":
    raise SystemExit(main())
