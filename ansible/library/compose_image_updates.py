#!/usr/bin/python
# -*- coding: utf-8 -*-
"""Bump pinned image tags in a docker-compose file to the newest release that is old enough.

Stdlib only (no skopeo/crane/docker needed): talks to the OCI distribution (registry v2) API
directly, with anonymous bearer-token auth, so it works against Docker Hub, ghcr.io, lscr.io,
codeberg.org and any other standard registry hosting public images.
"""

DOCUMENTATION = r"""
module: compose_image_updates
short_description: Update pinned image tags in a compose file after a cooldown period
description:
  - Reads every C(image:) line of a docker-compose file, lists the tags of each image's
    repository and picks the highest version tag with the same shape as the current one
    (same prefix, same suffix, same number of version components).
  - A candidate is only accepted when its image config C(created) timestamp is at least
    O(min_age_days) old, so freshly published releases get time to have bugs found and
    hot-fixed before they land here.
  - Unversioned/floating tags (C(latest), C(16), C(${VAR}) ...) are reported as unchanged.
  - The file is rewritten in place, touching only the tag text, so comments and formatting
    are preserved. Supports check mode and diff mode.
options:
  path: {description: Compose file to update., required: true, type: path}
  min_age_days: {description: Minimum age of a release before it is adopted., type: int, default: 14}
  allow_major: {description: Allow bumping the first version component., type: bool, default: false}
  platform: {description: Platform whose manifest is used when an image is multi-arch., type: str, default: linux/amd64}
  exclude: {description: Image names (without tag) to leave alone., type: list, elements: str, default: []}
  max_inspect: {description: Max candidate tags to inspect per image (newest first)., type: int, default: 10}
  timeout: {description: HTTP timeout in seconds., type: int, default: 30}
"""

import json
import os
import re
import tempfile
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone

from ansible.module_utils.basic import AnsibleModule

MANIFEST_ACCEPT = ", ".join([
    "application/vnd.oci.image.index.v1+json",
    "application/vnd.docker.distribution.manifest.list.v2+json",
    "application/vnd.oci.image.manifest.v1+json",
    "application/vnd.docker.distribution.manifest.v2+json",
])
INDEX_TYPES = (
    "application/vnd.oci.image.index.v1+json",
    "application/vnd.docker.distribution.manifest.list.v2+json",
)
IMAGE_LINE_RE = re.compile(r"""^(?P<lead>\s*image:\s*["']?)(?P<ref>[^\s"'#]+)(?P<trail>["']?\s*(?:#.*)?)$""")
# prefix (no digits) + dotted numeric version + suffix, e.g. "release-v" "1.6.0" "" / "" "3.20" "-alpine"
TAG_RE = re.compile(r"^(?P<prefix>[^\d]*)(?P<ver>\d+(?:\.\d+)*)(?P<suffix>.*)$")


class _StripAuthOnCrossHostRedirect(urllib.request.HTTPRedirectHandler):
    """Blob downloads redirect to a CDN/S3; forwarding the registry bearer token there breaks."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        new = super().redirect_request(req, fp, code, msg, headers, newurl)
        if new is not None and urllib.parse.urlsplit(newurl).netloc != urllib.parse.urlsplit(req.full_url).netloc:
            new.remove_header("Authorization")
        return new


class Registry:
    def __init__(self, host, repo, timeout):
        self.base = "https://%s/v2/%s" % (host, repo)
        self.timeout = timeout
        self.token = None
        self.opener = urllib.request.build_opener(_StripAuthOnCrossHostRedirect)

    def _fetch_token(self, www_authenticate):
        scheme, _, params = www_authenticate.partition(" ")
        if scheme.lower() != "bearer":
            raise RuntimeError("unsupported registry auth scheme: %s" % scheme)
        fields = dict(re.findall(r'(\w+)="([^"]*)"', params))
        realm = fields.pop("realm")
        with self.opener.open(realm + "?" + urllib.parse.urlencode(fields), timeout=self.timeout) as resp:
            body = json.load(resp)
        self.token = body.get("token") or body.get("access_token")

    def get(self, url, accept=None):
        """Returns (headers, parsed JSON body). Handles one anonymous token challenge."""
        for attempt in (1, 2):
            req = urllib.request.Request(url)
            if accept:
                req.add_header("Accept", accept)
            if self.token:
                req.add_header("Authorization", "Bearer " + self.token)
            try:
                with self.opener.open(req, timeout=self.timeout) as resp:
                    return resp.headers, json.load(resp)
            except urllib.error.HTTPError as e:
                challenge = e.headers.get("WWW-Authenticate")
                if e.code == 401 and attempt == 1 and challenge:
                    self._fetch_token(challenge)
                    continue
                raise

    def tags(self):
        url, tags = self.base + "/tags/list?n=1000", []
        while url:
            headers, body = self.get(url)
            tags.extend(body.get("tags") or [])
            m = re.search(r'<([^>]+)>;\s*rel="next"', headers.get("Link", ""))
            url = urllib.parse.urljoin(self.base, m.group(1)) if m else None
        return tags

    def created(self, tag, platform):
        """Image config 'created' timestamp for tag (platform-specific manifest if multi-arch)."""
        _, manifest = self.get("%s/manifests/%s" % (self.base, tag), MANIFEST_ACCEPT)
        if manifest.get("mediaType") in INDEX_TYPES or "manifests" in manifest:
            os_, _, arch = platform.partition("/")
            match = next((m for m in manifest["manifests"]
                          if m.get("platform", {}).get("os") == os_
                          and m.get("platform", {}).get("architecture") == arch), None)
            if match is None:
                return None
            _, manifest = self.get("%s/manifests/%s" % (self.base, match["digest"]), MANIFEST_ACCEPT)
        _, config = self.get("%s/blobs/%s" % (self.base, manifest["config"]["digest"]))
        return parse_time(config.get("created"))


def parse_time(value):
    if not value:
        return None
    # RFC3339 with up to nanosecond precision -> trim fraction to microseconds for fromisoformat
    value = re.sub(r"(\.\d{6})\d+", r"\1", value.replace("Z", "+00:00"))
    ts = datetime.fromisoformat(value)
    if ts.tzinfo is None:
        ts = ts.replace(tzinfo=timezone.utc)
    # Reproducible builds stamp 1970-01-01: that says nothing about release age, treat as unknown.
    return ts if ts.year >= 2000 else None


def split_ref(ref):
    """'ghcr.io/a/b:1.0' -> ('ghcr.io', 'a/b', 'ghcr.io/a/b', '1.0'); digests are not handled."""
    name, _, tag = ref.rpartition(":")
    if not name or "/" in tag or "@" in ref:
        return None
    first, _, rest = name.partition("/")
    if rest and ("." in first or ":" in first or first == "localhost"):
        host, repo = first, rest
    else:
        host, repo = "registry-1.docker.io", name if "/" in name else "library/" + name
    return host, repo, name, tag


def version_of(tag):
    m = TAG_RE.match(tag)
    if not m:
        return None
    return m.group("prefix"), tuple(int(p) for p in m.group("ver").split(".")), m.group("suffix")


def find_update(ref, params, cutoff):
    parts = split_ref(ref)
    if parts is None:
        return None, "not a name:tag reference"
    host, repo, name, tag = parts
    if name in params["exclude"]:
        return None, "excluded"
    current = version_of(tag)
    if current is None or len(current[1]) < 2:
        return None, "floating/unversioned tag"
    prefix, cur_ver, suffix = current

    reg = Registry(host, repo, params["timeout"])
    candidates = []
    for t in reg.tags():
        v = version_of(t)
        if (v and v[0] == prefix and v[2] == suffix and len(v[1]) == len(cur_ver) and v[1] > cur_ver
                and (params["allow_major"] or v[1][0] == cur_ver[0])):
            candidates.append((v[1], t))
    if not candidates:
        return None, "up to date"

    candidates.sort(reverse=True)
    too_new = []
    for _, t in candidates[:params["max_inspect"]]:
        created = reg.created(t, params["platform"])
        if created is None:
            continue
        if created <= cutoff:
            return {"image": name, "from": tag, "to": t, "created": created.isoformat(),
                    "held_back": too_new}, None
        too_new.append({"tag": t, "created": created.isoformat()})
    reason = "newer tags not old enough yet" if too_new else "could not determine age of newer tags"
    return None, "%s (%s)" % (reason, ", ".join(t for _, t in candidates[:params["max_inspect"]]))


def main():
    module = AnsibleModule(
        argument_spec=dict(
            path=dict(type="path", required=True),
            min_age_days=dict(type="int", default=14),
            allow_major=dict(type="bool", default=False),
            platform=dict(type="str", default="linux/amd64"),
            exclude=dict(type="list", elements="str", default=[]),
            max_inspect=dict(type="int", default=10),
            timeout=dict(type="int", default=30),
        ),
        supports_check_mode=True,
    )
    p = module.params
    cutoff = datetime.now(timezone.utc) - timedelta(days=p["min_age_days"])

    with open(p["path"]) as f:
        original = f.read()

    lines = original.splitlines(keepends=True)
    updates, unchanged, errors = [], [], []
    for i, line in enumerate(lines):
        m = IMAGE_LINE_RE.match(line.rstrip("\r\n"))
        if not m:
            continue
        ref = m.group("ref")
        try:
            update, reason = find_update(ref, p, cutoff)
        except Exception as e:  # one unreachable registry must not block the other images
            errors.append({"image": ref, "error": "%s: %s" % (type(e).__name__, e)})
            continue
        if update is None:
            unchanged.append({"image": ref, "reason": reason})
            continue
        updates.append(update)
        newline = line[len(line.rstrip("\r\n")):]
        lines[i] = m.group("lead") + "%s:%s" % (update["image"], update["to"]) + m.group("trail") + newline

    updated = "".join(lines)
    changed = updated != original
    if changed and not module.check_mode:
        module.atomic_move(_write_tmp(module, updated), p["path"])

    result = dict(changed=changed, path=p["path"], updates=updates, unchanged=unchanged, errors=errors)
    if module._diff and changed:
        result["diff"] = dict(before=original, after=updated,
                              before_header=p["path"], after_header=p["path"])
    module.exit_json(**result)


def _write_tmp(module, content):
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(module.params["path"]) or ".")
    with os.fdopen(fd, "w") as f:
        f.write(content)
    os.chmod(tmp, os.stat(module.params["path"]).st_mode & 0o7777)
    return tmp


if __name__ == "__main__":
    main()
