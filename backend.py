import os
import requests
from packaging.version import Version, InvalidVersion

GITHUB_API = "https://api.github.com"

def get_repo_from_env():
    owner = os.getenv("APP_GITHUB_OWNER", "").strip()
    repo  = os.getenv("APP_GITHUB_REPO", "").strip()
    if not owner or not repo:
        raise RuntimeError("GitHub owner/repo not set (APP_GITHUB_OWNER / APP_GITHUB_REPO).")
    return owner, repo

def get_latest_release_tag(timeout=8):
    """Return latest non-draft, non-prerelease release tag (e.g., 'v1.2.3')."""
    owner, repo = get_repo_from_env()
    url = f"{GITHUB_API}/repos/{owner}/{repo}/releases/latest"
    headers = {"Accept": "application/vnd.github+json", "User-Agent": "myapp-update-check"}
    r = requests.get(url, headers=headers, timeout=timeout)
    r.raise_for_status()
    data = r.json()
    return data.get("tag_name", "").strip()

def normalize_tag(tag):
    """Strip leading 'v' to compare as numeric versions; keep original for display."""
    t = (tag or "").strip()
    return t[1:] if t.lower().startswith("v") else t

def compare_versions(current_tag: str, latest_tag: str):
    """
    Return -1 if current < latest (update available),
            0 if equal,
            1 if current > latest (ahead/local build).
    """
    cur = normalize_tag(current_tag)
    lat = normalize_tag(latest_tag)
    try:
        vc, vl = Version(cur), Version(lat)
    except InvalidVersion:
        # fallback: plain string compare (not ideal, but avoids crashes)
        return (cur > lat) - (cur < lat)
    return (vc > vl) - (vc < vl)
