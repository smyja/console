import json
import re
from collections import OrderedDict
from datetime import datetime

import yaml

from utils import (
    clean_kube_version,
    current_kube_version,
    fetch_page,
    get_kube_release_info,
    print_error,
    print_warning,
    update_compatibility_info,
    validate_semver,
)

APP_NAME = "metallb"
README_URL = "https://raw.githubusercontent.com/metallb/metallb/main/website/content/_index.md"
INDEX_URL = "https://metallb.github.io/metallb/index.yaml"
TARGET_FILE = f"../../static/compatibilities/{APP_NAME}.yaml"
MIN_VERSION_PATTERN = re.compile(
    r"Kubernetes\s+(\d+\.\d+)(?:\.\d+)?\s+or\s+later", re.IGNORECASE
)


def extract_minimum_minor(markdown: str) -> str:
    match = MIN_VERSION_PATTERN.search(markdown)
    if match:
        return match.group(1)
    return "1.13"


def normalize_minor(value: str) -> str | None:
    match = re.search(r"(\d+)\.(\d+)", value)
    if not match:
        return None
    return f"{int(match.group(1))}.{int(match.group(2))}"


def compare_minor(lhs: str, rhs: str) -> int:
    l_major, l_minor = map(int, lhs.split("."))
    r_major, r_minor = map(int, rhs.split("."))
    if l_major != r_major:
        return l_major - r_major
    return l_minor - r_minor


def increment_minor(value: str) -> str:
    major, minor = map(int, value.split("."))
    minor += 1
    return f"{major}.{minor}"


def decrement_minor(value: str) -> str:
    major, minor = map(int, value.split("."))
    minor -= 1
    if minor < 0:
        if major == 0:
            return "0.0"
        major -= 1
        minor = 99
    return f"{major}.{minor}"


def build_minor_range(start: str, end: str) -> list[str]:
    if compare_minor(start, end) > 0:
        start, end = end, start

    major, minor = map(int, start.split("."))
    end_major, end_minor = map(int, end.split("."))

    result: list[str] = []
    while True:
        result.append(f"{major}.{minor}")
        if major == end_major and minor == end_minor:
            break
        minor += 1
        if minor >= 100:
            major += 1
            minor = 0
    return result


def parse_kube_constraint(
    constraint: str, fallback_min: str, fallback_max: str
) -> tuple[str, str]:
    min_minor = fallback_min
    max_minor = fallback_max

    for token in constraint.split(","):
        token = token.strip()
        if not token:
            continue

        match = re.match(r"(>=|<=|>|<)\s*v?([^\s]+)", token)
        if not match:
            continue
        operator, value = match.groups()
        minor = normalize_minor(value)
        if not minor:
            continue

        if operator == ">=":
            if compare_minor(minor, min_minor) > 0:
                min_minor = minor
        elif operator == ">":
            inc = increment_minor(minor)
            if compare_minor(inc, min_minor) > 0:
                min_minor = inc
        elif operator == "<=":
            if compare_minor(minor, max_minor) < 0:
                max_minor = minor
        elif operator == "<":
            dec = decrement_minor(minor)
            if compare_minor(dec, max_minor) < 0:
                max_minor = dec

    if compare_minor(min_minor, max_minor) > 0:
        min_minor = fallback_min
        max_minor = fallback_max

    return min_minor, max_minor


def parse_timestamp(value: str | None) -> datetime | None:
    if not value:
        return None
    if value.endswith("Z"):
        value = value.replace("Z", "+00:00")
    try:
        return datetime.fromisoformat(value)
    except ValueError:
        return None


def fetch_repo_release_data(owner: str, repo: str, pages: int = 5) -> list[dict]:
    aggregated: list[dict] = []
    for page in range(1, pages + 1):
        content = fetch_page(
            f"https://api.github.com/repos/{owner}/{repo}/releases?page={page}&per_page=100"
        )
        if not content:
            break

        try:
            page_data = json.loads(content)
        except json.JSONDecodeError as exc:
            print_error(f"Failed to parse MetalLB releases JSON: {exc}")
            break

        if not page_data:
            break

        aggregated.extend(page_data)

    return aggregated


def fetch_release_timestamps() -> dict[str, datetime | None]:
    timestamps: dict[str, datetime | None] = {}

    for release in fetch_repo_release_data("metallb", "metallb"):
        if release.get("draft") or release.get("prerelease"):
            continue
        tag = str(release.get("tag_name", "")).lstrip("v")
        semver = validate_semver(tag)
        if not semver:
            continue
        ts = parse_timestamp(release.get("published_at")) or parse_timestamp(
            release.get("created_at")
        )
        timestamps[str(semver)] = ts

    return timestamps


def fetch_kube_release_index_fallback() -> list[tuple[str, datetime]]:
    seen: set[str] = set()
    prepared: list[tuple[str, datetime]] = []

    for release in fetch_repo_release_data("kubernetes", "kubernetes", pages=3):
        tag = str(release.get("tag_name", ""))
        if not tag or "-" in tag:
            continue
        cleaned = clean_kube_version(tag)
        if not cleaned or cleaned in seen:
            continue

        ts = parse_timestamp(release.get("created_at")) or parse_timestamp(
            release.get("published_at")
        )
        if not ts:
            continue

        seen.add(cleaned)
        prepared.append((cleaned, ts))

    prepared.sort(key=lambda item: item[1])
    return prepared


def prepare_kube_release_index() -> list[tuple[str, datetime]]:
    prepared: list[tuple[str, datetime]] = []
    try:
        release_info = list(get_kube_release_info())
    except Exception as exc:
        print_warning(
            f"Falling back to custom Kubernetes release index for MetalLB: {exc}"
        )
        release_info = []

    if not release_info:
        release_info = fetch_kube_release_index_fallback()

    for tag, ts in release_info:
        cleaned = clean_kube_version(tag)
        if cleaned and ts:
            prepared.append((cleaned, ts))
    prepared.sort(key=lambda item: item[1])
    return prepared


KUBE_RELEASE_INDEX = prepare_kube_release_index()


def latest_kube_minor_for_timestamp(
    release_ts: datetime | None, fallback: str
) -> str:
    if not release_ts or not KUBE_RELEASE_INDEX:
        return fallback

    for minor, kube_ts in reversed(KUBE_RELEASE_INDEX):
        if kube_ts <= release_ts:
            return minor
    return fallback


def load_chart_entries() -> OrderedDict[str, dict]:
    content = fetch_page(INDEX_URL)
    if not content:
        print_error("Failed to download MetalLB Helm index.")
        return OrderedDict()

    try:
        index_data = yaml.safe_load(content)
    except yaml.YAMLError as exc:
        print_error(f"Failed to parse MetalLB Helm index: {exc}")
        return OrderedDict()

    entries = index_data.get("entries", {}).get("metallb", [])
    versions: OrderedDict[str, dict] = OrderedDict()
    for entry in entries:
        app_version = str(entry.get("appVersion", "")).lstrip("v")
        chart_version = str(entry.get("version", "")).lstrip("v")
        kube_constraint = entry.get("kubeVersion")
        if (
            not app_version
            or not kube_constraint
            or app_version == "0.0.0"
        ):
            continue
        if chart_version in {"", "0.0.0"}:
            chart_version_value = None
        else:
            chart_version_value = chart_version
        if app_version in versions:
            continue
        versions[app_version] = {
            "chart_version": chart_version_value,
            "kube_constraint": kube_constraint,
        }

    return versions


def scrape():
    readme = fetch_page(README_URL)
    if not readme:
        print_error("Failed to download MetalLB README.")
        return

    minimum_minor = extract_minimum_minor(readme.decode("utf-8", errors="replace"))

    latest_minor = current_kube_version()
    if not latest_minor:
        print_error("Unable to determine the current Kubernetes version.")
        return

    release_timestamps = fetch_release_timestamps()

    chart_entries = load_chart_entries()
    if not chart_entries:
        print_error("No MetalLB chart entries with kubeVersion found.")
        return

    versions: list[OrderedDict] = []
    sorted_versions = sorted(
        chart_entries.keys(), key=lambda v: validate_semver(v), reverse=True
    )

    for version in sorted_versions:
        data = chart_entries[version]
        release_ts = release_timestamps.get(version)
        max_minor_fallback = latest_kube_minor_for_timestamp(release_ts, latest_minor)
        min_minor, max_minor = parse_kube_constraint(
            data["kube_constraint"], minimum_minor, max_minor_fallback
        )
        kube_range = build_minor_range(min_minor, max_minor)
        version_entry = OrderedDict(
            [
                ("version", version),
                ("kube", kube_range),
                ("requirements", []),
                ("incompatibilities", []),
            ]
        )
        if data.get("chart_version"):
            version_entry["chart_version"] = data["chart_version"]
        versions.append(version_entry)

    update_compatibility_info(TARGET_FILE, versions)
