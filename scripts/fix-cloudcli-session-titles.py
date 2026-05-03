#!/usr/bin/env python3
import argparse
import json
import os
import sqlite3
import sys
from pathlib import Path


DEFAULT_CLOUDCLI_ROOT = Path("/usr/local/lib/node_modules/@cloudcli-ai/cloudcli")
DEFAULT_DB_PATH = Path("/home/claude/.cloudcli/auth.db")
DEFAULT_CLAUDE_HOME = Path("/home/claude/.claude")

TARGET_RELATIVE_PATH = Path(
    "dist-server/server/modules/providers/list/claude/claude-session-synchronizer.provider.js"
)

INTERNAL_TITLE_PREFIXES = [
    "<command-name>",
    "<command-message>",
    "<command-args>",
    "<local-command-stdout>",
    "<local-command-caveat>",
    "<system-reminder>",
    "Caveat:",
    "This session is being continued from a previous",
    "[Request interrupted",
]


def info(message: str) -> None:
    print(f"[fix-cloudcli-session-titles] {message}")


def warn(message: str) -> None:
    print(f"[fix-cloudcli-session-titles][warn] {message}", file=sys.stderr)


def normalize_text(value: str | None) -> str:
    return " ".join((value or "").split()).strip()


def is_meaningful_user_text(value: str | None) -> bool:
    normalized = normalize_text(value)
    if not normalized:
        return False
    return not any(normalized.startswith(prefix) for prefix in INTERNAL_TITLE_PREFIXES)


def extract_text_candidates(message_content) -> list[str]:
    if isinstance(message_content, str):
        return [message_content]

    if isinstance(message_content, list):
        results: list[str] = []
        for part in message_content:
            if not isinstance(part, dict):
                continue
            if part.get("type") != "text":
                continue
            text = part.get("text")
            if isinstance(text, str):
                results.append(text)
        return results

    return []


def resolve_jsonl_path(jsonl_path: Path, claude_home: Path) -> Path:
    if jsonl_path.exists():
        return jsonl_path

    container_prefix = Path("/home/claude/.claude")
    try:
        relative = jsonl_path.relative_to(container_prefix)
    except ValueError:
        return jsonl_path

    remapped = claude_home / relative
    return remapped


def derive_title_from_jsonl(jsonl_path: Path, claude_home: Path) -> str | None:
    resolved_path = resolve_jsonl_path(jsonl_path, claude_home)
    try:
        with resolved_path.open("r", encoding="utf-8") as handle:
            for raw_line in handle:
                line = raw_line.strip()
                if not line:
                    continue

                payload = json.loads(line)
                message = payload.get("message")
                if not isinstance(message, dict):
                    continue
                if message.get("role") != "user":
                    continue

                for candidate in extract_text_candidates(message.get("content")):
                    if is_meaningful_user_text(candidate):
                        return normalize_text(candidate)[:120]
    except FileNotFoundError:
        return None
    except Exception as exc:
        warn(f"Failed to parse {resolved_path}: {exc}")

    return None


def patch_cloudcli_file(cloudcli_root: Path) -> None:
    target_file = cloudcli_root / TARGET_RELATIVE_PATH
    if not target_file.exists():
        raise FileNotFoundError(f"CloudCLI target file not found: {target_file}")

    content = target_file.read_text(encoding="utf-8")
    if "INTERNAL_TITLE_PREFIXES" in content and "extractMeaningfulUserText" in content:
        info(f"Patch already present: {target_file}")
        return

    replacement_import_block = (
        "import fs from 'node:fs';\n"
        "import os from 'node:os';\n"
        "import path from 'node:path';\n"
        "import readline from 'node:readline';\n"
        "import { sessionsDb } from '../../../../modules/database/index.js';\n"
        "import { buildLookupMap, findFilesRecursivelyCreatedAfter, normalizeSessionName, readFileTimestamps, } from '../../../../shared/utils.js';\n"
        "const INTERNAL_TITLE_PREFIXES = [\n"
        "    '<command-name>',\n"
        "    '<command-message>',\n"
        "    '<command-args>',\n"
        "    '<local-command-stdout>',\n"
        "    '<local-command-caveat>',\n"
        "    '<system-reminder>',\n"
        "    'Caveat:',\n"
        "    'This session is being continued from a previous',\n"
        "    '[Request interrupted',\n"
        "];\n"
        "function normalizeTitleText(value) {\n"
        "    return (value ?? '').replace(/\\s+/g, ' ').trim();\n"
        "}\n"
        "function isMeaningfulUserText(value) {\n"
        "    const normalized = normalizeTitleText(value);\n"
        "    if (!normalized) {\n"
        "        return false;\n"
        "    }\n"
        "    return !INTERNAL_TITLE_PREFIXES.some((prefix) => normalized.startsWith(prefix));\n"
        "}\n"
        "function extractMeaningfulUserText(message) {\n"
        "    if (!message || message.role !== 'user') {\n"
        "        return undefined;\n"
        "    }\n"
        "    const candidates = [];\n"
        "    if (typeof message.content === 'string') {\n"
        "        candidates.push(message.content);\n"
        "    }\n"
        "    else if (Array.isArray(message.content)) {\n"
        "        for (const part of message.content) {\n"
        "            if (part?.type === 'text' && typeof part.text === 'string') {\n"
        "                candidates.push(part.text);\n"
        "            }\n"
        "        }\n"
        "    }\n"
        "    for (const candidate of candidates) {\n"
        "        if (isMeaningfulUserText(candidate)) {\n"
        "            return normalizeTitleText(candidate);\n"
        "        }\n"
        "    }\n"
        "    return undefined;\n"
        "}\n"
    )

    new_method = (
        "    async processSessionFile(filePath, nameMap) {\n"
        "        let sessionId;\n"
        "        let projectPath;\n"
        "        let fallbackTitle;\n"
        "        try {\n"
        "            const fileStream = fs.createReadStream(filePath);\n"
        "            const lineReader = readline.createInterface({ input: fileStream, crlfDelay: Infinity });\n"
        "            for await (const line of lineReader) {\n"
        "                const trimmed = line.trim();\n"
        "                if (!trimmed) {\n"
        "                    continue;\n"
        "                }\n"
        "                let data;\n"
        "                try {\n"
        "                    data = JSON.parse(trimmed);\n"
        "                }\n"
        "                catch {\n"
        "                    continue;\n"
        "                }\n"
        "                if (!sessionId && typeof data.sessionId === 'string') {\n"
        "                    sessionId = data.sessionId;\n"
        "                }\n"
        "                if (!projectPath && typeof data.cwd === 'string') {\n"
        "                    projectPath = data.cwd;\n"
        "                }\n"
        "                if (!fallbackTitle) {\n"
        "                    fallbackTitle = extractMeaningfulUserText(data.message);\n"
        "                }\n"
        "                if (sessionId && projectPath && (nameMap.get(sessionId) || fallbackTitle)) {\n"
        "                    break;\n"
        "                }\n"
        "            }\n"
        "        }\n"
        "        catch {\n"
        "            return null;\n"
        "        }\n"
        "        if (!sessionId || !projectPath) {\n"
        "            return null;\n"
        "        }\n"
        "        return {\n"
        "            sessionId,\n"
        "            projectPath,\n"
        "            sessionName: normalizeSessionName(nameMap.get(sessionId) ?? fallbackTitle, 'Untitled Claude Session'),\n"
        "        };\n"
        "    }\n"
    )

    comment_marker = "/**\n * Session indexer for Claude transcript artifacts.\n */\n"
    if comment_marker not in content:
        raise RuntimeError("Unexpected CloudCLI synchronizer structure; class comment not found")
    _, remainder = content.split(comment_marker, 1)
    content = replacement_import_block + comment_marker + remainder

    method_start = content.find("    async processSessionFile(filePath, nameMap) {")
    method_end = content.find("\n}\n//# sourceMappingURL", method_start)
    if method_start == -1 or method_end == -1:
        raise RuntimeError("Unexpected CloudCLI synchronizer method layout; processSessionFile not found")

    content = content[:method_start] + new_method + content[method_end:]
    target_file.write_text(content, encoding="utf-8")
    info(f"Patched CloudCLI synchronizer: {target_file}")


def backfill_database(db_path: Path, claude_home: Path) -> int:
    if not db_path.exists():
        warn(f"CloudCLI database not found, skipping backfill: {db_path}")
        return 0

    conn = sqlite3.connect(str(db_path))
    cur = conn.cursor()
    rows = cur.execute(
        """
        select session_id, jsonl_path
        from sessions
        where provider = 'claude'
          and custom_name = 'Untitled Claude Session'
        """
    ).fetchall()

    updated = 0
    for session_id, jsonl_path in rows:
        if not jsonl_path:
            continue

        title = derive_title_from_jsonl(Path(jsonl_path), claude_home)
        if not title:
            continue

        cur.execute(
            """
            update sessions
            set custom_name = ?
            where session_id = ?
              and provider = 'claude'
              and custom_name = 'Untitled Claude Session'
            """,
            (title, session_id),
        )
        updated += cur.rowcount

    conn.commit()
    conn.close()
    info(f"Backfilled {updated} Claude session title(s) in {db_path}")
    return updated


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--mode",
        choices=["build", "runtime", "all"],
        default="all",
        help="build: patch installed CloudCLI files; runtime: backfill DB; all: do both",
    )
    parser.add_argument(
        "--cloudcli-root",
        default=os.environ.get("CLOUDCLI_ROOT", str(DEFAULT_CLOUDCLI_ROOT)),
    )
    parser.add_argument(
        "--db-path",
        default=os.environ.get("CLOUDCLI_DB_PATH", str(DEFAULT_DB_PATH)),
    )
    parser.add_argument(
        "--claude-home",
        default=os.environ.get("CLOUDCLI_CLAUDE_HOME", str(DEFAULT_CLAUDE_HOME)),
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    cloudcli_root = Path(args.cloudcli_root)
    db_path = Path(args.db_path)
    claude_home = Path(args.claude_home)

    try:
        if args.mode in {"build", "all"}:
            patch_cloudcli_file(cloudcli_root)
        if args.mode in {"runtime", "all"}:
            backfill_database(db_path, claude_home)
    except Exception as exc:
        warn(str(exc))
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
