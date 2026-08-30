#!/usr/bin/env python3
"""query_adapter 的无第三方依赖边界回归。"""

from __future__ import annotations

import unittest

from query_adapter import bounded_range_values, normalize_window_start


def point(value: str = "0") -> dict[str, object]:
    return {"time": "0", "time_units": 0, "value": value, "hex": value}


def event(time_units: int, value: str) -> dict[str, object]:
    return {"time": f"{time_units}ps", "time_units": time_units, "value": value}


class NormalizeWindowStartTests(unittest.TestCase):
    def test_point_only_starts_normalized_window(self) -> None:
        normalized, boundary, reason = normalize_window_start(point(), [], 1)
        self.assertIsNone(reason)
        self.assertTrue(boundary["consistent"])
        self.assertEqual(normalized[0]["source"], "point_at_start")

    def test_matching_same_time_range_is_collapsed(self) -> None:
        normalized, boundary, reason = normalize_window_start(
            point(), [event(0, "0"), event(10, "1")], 1
        )
        self.assertIsNone(reason)
        self.assertEqual(boundary["same_timestamp_range_events"], 1)
        self.assertEqual([item["time_units"] for item in normalized], [0, 10])

    def test_empty_point_is_rejected(self) -> None:
        normalized, _boundary, reason = normalize_window_start(point(""), [], 1)
        self.assertIsNone(normalized)
        self.assertEqual(reason, "POINT_VALUE_INVALID")

    def test_conflicting_same_time_range_is_rejected(self) -> None:
        normalized, _boundary, reason = normalize_window_start(
            point("0"), [event(0, "1")], 1
        )
        self.assertIsNone(normalized)
        self.assertEqual(reason, "WINDOW_START_SEMANTICS_AMBIGUOUS")

    def test_out_of_order_range_is_rejected(self) -> None:
        normalized, _boundary, reason = normalize_window_start(
            point(), [event(10, "1"), event(5, "0")], 1
        )
        self.assertIsNone(normalized)
        self.assertEqual(reason, "BACKEND_PROTOCOL_MISMATCH")

    def test_width_and_four_state_are_checked(self) -> None:
        self.assertEqual(normalize_window_start(point("01"), [], 1)[2], "POINT_VALUE_INVALID")
        self.assertEqual(normalize_window_start(point("q"), [], 1)[2], "POINT_VALUE_INVALID")
        self.assertIsNone(normalize_window_start(point("x"), [], 1)[2])


class BoundedRangeTests(unittest.TestCase):
    def test_exact_cap_is_accepted(self) -> None:
        values = [event(index, "0") for index in range(4)]
        accepted, reason = bounded_range_values({"count": 4, "values": values}, 4)
        self.assertIsNone(reason)
        self.assertEqual(accepted, values)

    def test_cap_plus_one_is_inconclusive(self) -> None:
        values = [event(index, "0") for index in range(5)]
        accepted, reason = bounded_range_values({"count": 5, "values": values}, 4)
        self.assertIsNone(accepted)
        self.assertEqual(reason, "QUERY_RESULT_TRUNCATED_OR_OVER_BUDGET")

    def test_count_mismatch_is_rejected(self) -> None:
        accepted, reason = bounded_range_values({"count": 2, "values": [event(0, "0")]}, 4)
        self.assertIsNone(accepted)
        self.assertEqual(reason, "BACKEND_PROTOCOL_MISMATCH")


if __name__ == "__main__":
    unittest.main()
