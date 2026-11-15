#!/usr/bin/env python3
"""Small, dependency-free API load probe for local or staging environments.

The default target is local FastAPI. Remote targets require two explicit flags
and are capped at 100 requests so an accidental production stress test is
unlikely. Authorization and App Check tokens may be supplied through
environment variables but are never printed.
"""

from __future__ import annotations

import argparse
import json
import os
import statistics
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass
from urllib.error import HTTPError, URLError
from urllib.parse import urlparse
from urllib.request import Request, urlopen


@dataclass(frozen=True)
class Result:
    elapsed_ms: float
    status: int | None
    error: str | None


def _percentile(values: list[float], percentile: float) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    index = min(len(ordered) - 1, round((percentile / 100) * (len(ordered) - 1)))
    return ordered[index]


def _request(
    url: str,
    method: str,
    body: bytes | None,
    headers: dict[str, str],
    timeout: float,
) -> Result:
    started = time.perf_counter()
    try:
        request = Request(url, data=body, headers=headers, method=method)
        with urlopen(request, timeout=timeout) as response:
            response.read(1024)
            status = response.status
        return Result((time.perf_counter() - started) * 1000, status, None)
    except HTTPError as error:
        # Record only the status; response bodies may contain sensitive data.
        return Result((time.perf_counter() - started) * 1000, error.code, "http")
    except (TimeoutError, URLError, OSError):
        return Result((time.perf_counter() - started) * 1000, None, "network")


def _is_local(hostname: str) -> bool:
    return hostname in {"127.0.0.1", "localhost", "::1"}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-url", default="http://127.0.0.1:8000")
    parser.add_argument("--path", default="/health")
    parser.add_argument("--method", choices=("GET", "POST"), default="GET")
    parser.add_argument("--payload", help="JSON request body for POST")
    parser.add_argument("--requests", type=int, default=50)
    parser.add_argument("--concurrency", type=int, default=5)
    parser.add_argument("--timeout", type=float, default=10.0)
    parser.add_argument("--allow-remote", action="store_true")
    parser.add_argument(
        "--confirm-remote",
        action="store_true",
        help="Required with --allow-remote; confirms this is an approved test target.",
    )
    args = parser.parse_args()

    if args.requests < 1 or args.requests > 10_000:
        parser.error("--requests must be between 1 and 10000")
    if args.concurrency < 1 or args.concurrency > 100:
        parser.error("--concurrency must be between 1 and 100")
    if args.timeout <= 0 or args.timeout > 120:
        parser.error("--timeout must be between 0 and 120 seconds")

    base_url = args.base_url.rstrip("/")
    parsed = urlparse(base_url)
    if parsed.scheme not in {"http", "https"} or not parsed.hostname:
        parser.error("--base-url must be an absolute HTTP(S) URL")
    if not _is_local(parsed.hostname):
        if not (args.allow_remote and args.confirm_remote):
            parser.error(
                "Remote targets require --allow-remote --confirm-remote. "
                "Use staging or an approved low-volume window."
            )
        if args.requests > 100:
            parser.error("Remote probes are capped at 100 requests")

    if args.method == "POST" and args.payload is None:
        parser.error("--payload is required for POST")
    body = None
    headers = {"Accept": "application/json", "User-Agent": "ai-dsuhis-load-probe/1.0"}
    if args.method == "POST":
        try:
            body = json.dumps(json.loads(args.payload)).encode("utf-8")
        except (TypeError, json.JSONDecodeError) as error:
            parser.error(f"--payload must be valid JSON: {error}")
        headers["Content-Type"] = "application/json"

    firebase_token = os.getenv("LOAD_TEST_FIREBASE_ID_TOKEN", "").strip()
    app_check_token = os.getenv("LOAD_TEST_APPCHECK_TOKEN", "").strip()
    if firebase_token:
        headers["Authorization"] = f"Bearer {firebase_token}"
    if app_check_token:
        headers["X-Firebase-AppCheck"] = app_check_token

    url = f"{base_url}{args.path if args.path.startswith('/') else '/' + args.path}"
    started = time.perf_counter()
    results: list[Result] = []
    with ThreadPoolExecutor(max_workers=args.concurrency) as executor:
        futures = [
            executor.submit(_request, url, args.method, body, headers, args.timeout)
            for _ in range(args.requests)
        ]
        for future in as_completed(futures):
            results.append(future.result())
    total_seconds = max(time.perf_counter() - started, 0.000001)

    latencies = [result.elapsed_ms for result in results]
    successes = sum(1 for result in results if result.status is not None and 200 <= result.status < 400)
    status_counts: dict[str, int] = {}
    for result in results:
        key = str(result.status) if result.status is not None else result.error or "unknown"
        status_counts[key] = status_counts.get(key, 0) + 1

    print(f"target={base_url}{args.path} method={args.method}")
    print(f"requests={len(results)} concurrency={args.concurrency} timeout={args.timeout}s")
    print(f"successes={successes} errors={len(results) - successes} throughput={len(results) / total_seconds:.2f}/s")
    print(
        "latency_ms="
        f"p50:{_percentile(latencies, 50):.2f} "
        f"p95:{_percentile(latencies, 95):.2f} "
        f"max:{max(latencies, default=0):.2f} "
        f"mean:{statistics.mean(latencies) if latencies else 0:.2f}"
    )
    print("statuses=" + ",".join(f"{key}:{status_counts[key]}" for key in sorted(status_counts)))
    return 0 if successes == len(results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
