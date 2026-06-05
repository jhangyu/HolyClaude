#!/usr/bin/env python3
"""HolyClaude — Apprise Notification Script
Usage: notify.py stop | notify.py error
Only sends if ~/.claude/notify-on flag file exists AND NOTIFY_* env vars are set.
"""

import os
import sys
import argparse
import re


def sanitize(value, limit=120):
    if value is None:
        return ""
    text = str(value).replace("\x00", "")
    text = re.sub(r"\s+", " ", text).strip()
    if len(text) > limit:
        return text[: limit - 3].rstrip() + "..."
    return text


def parse_args(argv):
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("event", nargs="?", default="unknown")
    parser.add_argument("--provider")
    parser.add_argument("--session-name")
    parser.add_argument("--session-id")
    parser.add_argument("--reason")
    parser.add_argument("--error")
    args, _unknown = parser.parse_known_args(argv)
    return args


def provider_label(provider):
    label = sanitize(provider, 40)
    if not label:
        return ""
    return label[:1].upper() + label[1:]


def session_fragment(args):
    session = sanitize(args.session_name or args.session_id, 80)
    return f" Session: {session}." if session else ""


def provider_event(args):
    provider = provider_label(args.provider)
    if not provider:
        return None

    if args.event == "stop":
        title = f"HolyClaude — {provider} Task Complete"
        body = f"{provider} chat finished."
        reason = sanitize(args.reason, 120) if args.reason is not None else ""
        if reason:
            body += session_fragment(args) + f" Reason: {reason}."
        else:
            body += session_fragment(args)
        return title, body, "info"

    if args.event == "error":
        title = f"HolyClaude — {provider} Task Failed"
        body = f"{provider} chat failed."
        error = sanitize(args.error, 180) if args.error is not None else ""
        if error:
            body += session_fragment(args) + f" Error: {error}."
        else:
            body += session_fragment(args)
        return title, body, "warning"

    return None

def main():
    # Check if notifications are enabled
    flag_file = "/home/claude/.claude/notify-on"
    if not os.path.isfile(flag_file):
        sys.exit(0)

    # Collect all NOTIFY_* env vars
    urls = []
    for key, value in os.environ.items():
        if not key.startswith("NOTIFY_"):
            continue
        if not value or not value.strip():
            continue
        if key == "NOTIFY_URLS":
            # Catch-all: split on commas for multiple URLs
            urls.extend(u.strip() for u in value.split(",") if u.strip())
        else:
            urls.append(value.strip())

    if not urls:
        sys.exit(0)

    # Event mapping
    args = parse_args(sys.argv[1:])
    event = sanitize(args.event, 80)
    events = {
        "stop": ("HolyClaude — Task Complete", "Claude has finished the current task.", "info"),
        "error": ("HolyClaude — Something Went Wrong", "A tool use failure occurred. Check the session for details.", "warning"),
    }
    provider_details = provider_event(args)
    title, body, notify_type = provider_details or events.get(event, (
        "HolyClaude — Notification",
        f"Event: {event}",
        "info",
    ))

    # Send via Apprise — all failures silently ignored
    try:
        import apprise
        ap = apprise.Apprise()
        for url in urls:
            ap.add(url)
        ap.notify(title=title, body=body, notify_type=notify_type)
    except Exception:
        pass

    sys.exit(0)

if __name__ == "__main__":
    main()
