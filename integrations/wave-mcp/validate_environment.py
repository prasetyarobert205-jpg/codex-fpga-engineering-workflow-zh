#!/usr/bin/env python3
"""验证脱敏 wave-mcp 环境清单；不修改 PATH、venv 或全局配置。"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any


class ManifestError(RuntimeError):
    pass


def strict_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    value: dict[str, Any] = {}
    for key, item in pairs:
        if key in value:
            raise ManifestError(f"重复 JSON key：{key}")
        value[key] = item
    return value


def main() -> int:
    parser = argparse.ArgumentParser(description="验证 wave-mcp 本地/公开环境清单")
    parser.add_argument("config", type=Path)
    parser.add_argument("--allow-placeholders", action="store_true")
    args = parser.parse_args()
    data = json.loads(args.config.read_text(encoding="utf-8"), object_pairs_hook=strict_object)
    if not isinstance(data, dict):
        raise ManifestError("顶层必须是 JSON object")
    version = data.get("schema_version")
    if version == "portable-wave-mcp-environment-1.0":
        for field in ("scope", "python", "wave_mcp", "policy"):
            if field not in data:
                raise ManifestError(f"缺少字段：{field}")
        policy = data["policy"]
        if policy.get("modify_global_path") is not False or policy.get("modify_global_library_mapping") is not False:
            raise ManifestError("公开环境模板不得要求修改全局 PATH/library mapping")
        if data["wave_mcp"].get("required_version") != "0.1.1":
            raise ManifestError("当前公开适配层只冻结验证过的 wave-mcp 0.1.1")
        text = args.config.read_text(encoding="utf-8")
        if not args.allow_placeholders and "<" in text:
            raise ManifestError("清单仍含 placeholder；真实使用前请填写或删除可选字段")
    elif version == "sanitized-tested-wave-mcp-environment-1.0":
        if data.get("scope") != "ONE_PROJECT_DIAGNOSTIC_SMOKE":
            raise ManifestError("实测清单 scope 必须保持窄范围")
        privacy = data.get("privacy", {})
        if any(privacy.get(field) is not False for field in (
            "absolute_machine_paths_included",
            "project_or_customer_paths_included",
            "virtual_environment_binary_included",
        )):
            raise ManifestError("实测清单的隐私声明不完整")
        if data.get("wave_mcp", {}).get("version") != "0.1.1":
            raise ManifestError("实测 wave-mcp 版本不匹配")
        package_tree = data["wave_mcp"].get("package_tree", {})
        if (
            package_tree.get("included_glob") != "**/*.py"
            or package_tree.get("file_count") != 19
            or package_tree.get("entry_format") != "<relative-posix-path>:<full-file-sha256>"
            or package_tree.get("sort_order") != "relative path ascending"
            or package_tree.get("tree_algorithm") != "sha256(join(entries, LF))"
            or not re.fullmatch(r"[0-9a-f]{64}", str(package_tree.get("sha256", "")))
        ):
            raise ManifestError("实测 wave-mcp package tree 定义或 digest 不完整")
        dependencies = data["wave_mcp"].get("direct_dependencies", {})
        if dependencies != {"mcp": "2.1.1", "pylibfst": "0.2.1", "pyslang": "11.0.0"}:
            raise ManifestError("实测直接依赖版本与冻结组合不匹配")
    else:
        raise ManifestError(f"不支持的 schema_version：{version}")
    print(json.dumps({"status": "MANIFEST_VALID", "schema_version": version}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
