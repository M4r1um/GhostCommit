from __future__ import annotations

import csv
import json
import os
import random
import sys
import time
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

import requests

# settings
ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data"

REPOS = [
    "microsoft/vscode",
    "react/react",
    "pandas-dev/pandas",
    "fastapi/fastapi",
]

# months to collect (by created date)
MONTHS = [(2025, 1), (2025, 4), (2025, 7), (2025, 10)]

# None = take all issues, or a number to randomly sample per month
MAX_PER_STRATUM: int | None = None
RANDOM_SEED = 42

API = "https://api.github.com/search/issues"
PER_PAGE = 100
SEARCH_LIMIT = 1000  # github only returns 1000 results per search

FIELDS = [
    "repo", "number", "issue_id", "title", "state", "state_reason",
    "created_at", "updated_at", "closed_at", "comments", "labels",
    "label_count", "issue_type", "assignee_count", "author_association",
    "reactions_total", "is_locked", "html_url", "sample_month",
    "sample_weight", "snapshot_at",
]


# HTTP
def make_session() -> requests.Session:
    s = requests.Session()
    s.headers["Accept"] = "application/vnd.github+json"
    s.headers["X-GitHub-Api-Version"] = "2022-11-28"
    token = os.environ.get("GITHUB_TOKEN")
    if token:
        s.headers["Authorization"] = f"Bearer {token}"
    else:
        print("! No GITHUB_TOKEN set - running slowly (10 searches/minute).")
    return s


def search(session, query: str, page: int = 1, per_page: int = PER_PAGE) -> dict:
    # one search request, waits if rate limited
    params = {"q": query, "per_page": per_page, "page": page,
              "sort": "created", "order": "asc"}
    for attempt in range(6):
        r = session.get(API, params=params, timeout=30)
        if r.status_code == 200:
            remaining = int(r.headers.get("X-RateLimit-Remaining", "1"))
            if remaining == 0:
                _sleep_until(r.headers.get("X-RateLimit-Reset"))
            return r.json()
        if r.status_code in (403, 429):
            if r.headers.get("Retry-After"):
                wait = int(r.headers["Retry-After"]) + 1
                print(f"  secondary rate limit, waiting {wait}s")
                time.sleep(wait)
            else:
                _sleep_until(r.headers.get("X-RateLimit-Reset"))
            continue
        if r.status_code >= 500:
            time.sleep(2 ** attempt)
            continue
        # other errors (like 422) mean the query is wrong
        raise RuntimeError(f"GitHub {r.status_code} for {query!r}: {r.text[:300]}")
    raise RuntimeError(f"Gave up after retries: {query!r}")


def _sleep_until(reset_header):
    reset = int(reset_header) if reset_header else int(time.time()) + 60
    wait = max(reset - int(time.time()), 1) + 2
    print(f"  rate limit reached, waiting {wait}s")
    time.sleep(wait)


# windows
def month_bounds(year: int, month: int) -> tuple[date, date]:
    start = date(year, month, 1)
    nxt = date(year + (month == 12), month % 12 + 1, 1)
    return start, nxt - timedelta(days=1)


def query_for(repo: str, start: date, end: date) -> str:
    return f"repo:{repo} is:issue created:{start.isoformat()}..{end.isoformat()}"


def windows_under_limit(session, repo: str, start: date, end: date) -> list[tuple[date, date, int]]:
    # split the date range in half until each part has <= 1000 results
    total = search(session, query_for(repo, start, end), per_page=1)["total_count"]
    if total <= SEARCH_LIMIT or start == end:
        if total > SEARCH_LIMIT:
            print(f"  ! {repo} {start}: {total} issues in one day, only 1,000 retrievable")
        return [(start, end, total)]
    mid = start + (end - start) // 2
    return (windows_under_limit(session, repo, start, mid)
            + windows_under_limit(session, repo, mid + timedelta(days=1), end))


def fetch_window(session, repo: str, start: date, end: date, expected: int) -> list[dict]:
    items: list[dict] = []
    pages = min((expected + PER_PAGE - 1) // PER_PAGE, SEARCH_LIMIT // PER_PAGE)
    for page in range(1, pages + 1):
        batch = search(session, query_for(repo, start, end), page=page)["items"]
        items.extend(batch)
        if len(batch) < PER_PAGE:
            break
    return items


# records
def to_record(item: dict, repo: str, month_label: str, snapshot: str) -> dict:
    labels = [lab["name"] for lab in item.get("labels") or []]
    issue_type = (item.get("type") or {}).get("name") if isinstance(item.get("type"), dict) else None
    return {
        "repo": repo,
        "number": item["number"],
        "issue_id": item["id"],
        "title": (item.get("title") or "").replace("\n", " ").strip(),
        "state": item["state"],
        "state_reason": item.get("state_reason") or "",
        "created_at": item["created_at"],
        "updated_at": item["updated_at"],
        "closed_at": item.get("closed_at") or "",
        "comments": item.get("comments", 0),
        "labels": "|".join(labels),
        "label_count": len(labels),
        "issue_type": issue_type or "",
        "assignee_count": len(item.get("assignees") or []),
        "author_association": item.get("author_association") or "",
        "reactions_total": (item.get("reactions") or {}).get("total_count", 0),
        "is_locked": item.get("locked", False),
        "html_url": item["html_url"],
        "sample_month": month_label,
        "sample_weight": 1.0,
        "snapshot_at": snapshot,
    }


# main
def collect(session=None) -> tuple[list[dict], list[dict], str]:
    session = session or make_session()
    snapshot = datetime.now(timezone.utc).replace(microsecond=0).isoformat()
    rng = random.Random(RANDOM_SEED)
    rows: list[dict] = []
    coverage: list[dict] = []

    for repo in REPOS:
        for year, month in MONTHS:
            label = f"{year}-{month:02d}"
            start, end = month_bounds(year, month)
            windows = windows_under_limit(session, repo, start, end)
            population_reported = sum(w[2] for w in windows)

            found: dict[int, dict] = {}
            for w_start, w_end, w_total in windows:
                for item in fetch_window(session, repo, w_start, w_end, w_total):
                    if "pull_request" in item:  # skip pull requests
                        continue
                    found[item["number"]] = item

            population = list(found.values())
            if MAX_PER_STRATUM and len(population) > MAX_PER_STRATUM:
                chosen = rng.sample(population, MAX_PER_STRATUM)
            else:
                chosen = population
            weight = len(population) / len(chosen) if chosen else 0.0

            for item in chosen:
                rec = to_record(item, repo, label, snapshot)
                rec["sample_weight"] = round(weight, 4)
                rows.append(rec)

            n_open = sum(1 for i in population if i["state"] == "open")
            coverage.append({
                "repo": repo,
                "sample_month": label,
                "population_reported": population_reported,
                "population_fetched": len(population),
                "population_open": n_open,
                "population_closed": len(population) - n_open,
                "collected": len(chosen),
                "sample_weight": round(weight, 4),
                "windows_used": len(windows),
                "method": "census" if len(chosen) == len(population) else f"random_{MAX_PER_STRATUM}_seed{RANDOM_SEED}",
            })
            print(f"{repo:22s} {label}: population {len(population):5d} "
                  f"(open {n_open:4d}) collected {len(chosen):5d}")

    return rows, coverage, snapshot


def write_csv(path: Path, rows: list[dict], fields: list[str]):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        w.writerows(rows)


def main():
    rows, coverage, snapshot = collect()
    write_csv(DATA / "issues_v2.csv", rows, FIELDS)
    write_csv(DATA / "sample_coverage_v2.csv", coverage, list(coverage[0].keys()))
    (DATA / "collection_log.json").write_text(json.dumps({
        "snapshot_at": snapshot,
        "repos": REPOS,
        "months": [f"{y}-{m:02d}" for y, m in MONTHS],
        "max_per_stratum": MAX_PER_STRATUM,
        "random_seed": RANDOM_SEED,
        "issues_written": len(rows),
    }, indent=2))
    print(f"\nWrote {len(rows)} issues to data/issues_v2.csv (snapshot {snapshot})")


if __name__ == "__main__":
    try:
        main()
    except RuntimeError as e:
        sys.exit(f"Error: {e}")
