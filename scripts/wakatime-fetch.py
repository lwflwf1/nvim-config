#!/usr/bin/env python3
"""wakatime ferry receiver - pull exported heartbeat archives out of a mailbox.

The air-gapped RHEL6 box cannot reach wakapi, so it mails its heartbeat export
out with `ferry pack` + `ferry email` (one email per <=1 MiB part, subject
"Directory Archive: wakatime-YYYYMMDD.zip [i/N]"). This tool is the receiving
end: it finds those parts in a mail folder, reassembles them with ferry itself
(no second merge implementation to drift), and can replay the heartbeats into a
self-hosted wakapi.

Subcommands are added read-only-first on purpose -- `folders` and `scan` never
modify the mailbox, so they are safe to run against a real work inbox to verify
that the Outlook rule and the folder path are actually right.

    scan    connect, EXAMINE the folder, and report which archives are present
            and whether every part arrived. Reads only Subject headers, using
            BODY.PEEK, so nothing is marked as seen. Also checks INBOX so a
            non-firing rule is visible.

    folders list every IMAP folder with the server's delimiter, so the `folder`
            setting can be filled in exactly (Exchange maps Outlook's
            "Inbox/sub" to IMAP "INBOX/sub", but not always).

    fetch   download a complete archive's attachments and prove they survived
            the mail path: ferry merges the parts and unpacks the result, so a
            gateway that rewrote line endings surfaces as a zip CRC failure
            instead of silently corrupting the heartbeats.

    sync    (not implemented yet) fetch -> POST the heartbeats into wakapi

Config: JSON, tried in this order -- --config, ./imap.json, next to this script.

    {
        "host": "mail.asrmicro.com",
        "port": 993,
        "user": "DOMAIN\\username or user@domain",
        "password": "...",
        "folder": "INBOX/wakatime",
        "subject_filter": "Directory Archive: wakatime-",
        "ferry": "G:\\ai\\scripts\\ferry\\ferry.py",
        "insecure": false
    }

Output is deliberately ASCII-only: a Windows console running under a GBK code
page cannot encode box-drawing or check-mark characters and the resulting
UnicodeEncodeError looks like a crash mid-operation.
"""

import argparse
import base64
import configparser
import email
import email.policy
import json
import os
import re
import shutil
import ssl
import subprocess
import sys
import urllib.error
import urllib.request
from datetime import datetime
from email.header import decode_header
from imaplib import IMAP4_SSL, IMAP4
from pathlib import Path
from typing import Any, Dict, List, NoReturn, Optional, Tuple

DEFAULT_SUBJECT_FILTER = "Directory Archive: wakatime-"
CONFIG_NAME = "imap.json"

LIST_RE = re.compile(r'^\((?P<flags>[^)]*)\)\s+"(?P<delim>[^"]*)"\s+(?P<name>.*)$')
PART_RE = re.compile(r"^(?P<base>.+?)\.part(?P<idx>\d+)(?P<ext>\.[^.]+)$")


def out(msg=""):
    sys.stdout.write(msg + "\n")
    sys.stdout.flush()


def die(msg: str, code: int = 1) -> NoReturn:
    sys.stderr.write("error: " + msg + "\n")
    sys.stderr.flush()
    sys.exit(code)


# ---------------------------------------------------------------- config


def load_config(explicit: Optional[str]) -> Dict[str, Any]:
    script_dir = Path(__file__).resolve().parent
    candidates: List[Path] = []
    if explicit:
        candidates.append(Path(explicit))
    else:
        candidates += [Path.cwd() / CONFIG_NAME, script_dir / CONFIG_NAME]

    for p in candidates:
        if p.is_file():
            try:
                cfg: Dict[str, Any] = json.loads(p.read_text(encoding="utf-8"))
            except (OSError, ValueError) as e:
                die("%s is not valid JSON: %s" % (p, e))
            cfg["_path"] = str(p)
            return cfg

    die(
        "no config found. Looked for: %s\n"
        "       create one with host/port/user/password/folder (see the docstring)"
        % ", ".join(str(c) for c in candidates)
    )


def require(cfg: Dict[str, Any], key: str) -> str:
    v = cfg.get(key)
    if v in (None, ""):
        die("config %s is missing the %r key" % (cfg["_path"], key))
    return str(v)


# ---------------------------------------------------------------- imap


def connect(cfg):
    host = require(cfg, "host")
    port = int(cfg.get("port") or 993)
    if cfg.get("insecure"):
        ctx = ssl.create_default_context()
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
        out("warning: TLS verification disabled (config 'insecure': true)")
    else:
        ctx = ssl.create_default_context()
    try:
        srv = IMAP4_SSL(host, port, ssl_context=ctx, timeout=20)
    except ssl.SSLCertVerificationError as e:
        die(
            "TLS verification failed for %s:%d: %s\n"
            "       if this machine does not trust the server's CA, set "
            '"insecure": true in %s' % (host, port, e, cfg["_path"])
        )
    except OSError as e:
        die("cannot reach %s:%d: %s" % (host, port, e))

    user = require(cfg, "user")
    password = require(cfg, "password")
    try:
        srv.login(user, password)
    except IMAP4.error as e:
        die("login failed for %r: %s\n"
            "       Exchange usually wants DOMAIN\\\\user or user@domain; also "
            "check that IMAP is enabled on the mailbox" % (user, e))
    return srv


def decode_mutf7(name: str) -> str:
    """Decode IMAP's modified UTF-7 folder names (Exchange/Outlook non-ASCII).

    Without this the listing is unreadable ('&g0l6Pw-'), which makes picking the
    right `folder` value guesswork. Implemented inline so the script stays
    dependency-free ('&' starts a base64 run terminated by '-', ',' stands in for
    '/', and '&-' is a literal ampersand; ASCII passes through untouched).
    """
    if "&" not in name:
        return name
    out: List[str] = []
    i = 0
    while i < len(name):
        if name[i] != "&":
            out.append(name[i])
            i += 1
            continue
        end = name.find("-", i)
        if end < 0:
            out.append(name[i:])
            break
        if end == i + 1:
            out.append("&")
        else:
            b64 = name[i + 1:end].replace(",", "/")
            b64 += "=" * (-len(b64) % 4)
            try:
                out.append(base64.b64decode(b64).decode("utf-16-be"))
            except (ValueError, UnicodeDecodeError):
                out.append(name[i:end + 1])
        i = end + 1
    return "".join(out)


def imap_quote(name: str) -> str:
    """Quote a mailbox name for SELECT. Always legal, and required when the name
    has spaces (imaplib passes arguments through verbatim)."""
    return '"' + name.replace("\\", "\\\\").replace('"', '\\"') + '"'


def list_folders(srv):
    typ, data = srv.list()
    if typ != "OK":
        die("LIST failed: %s" % data)
    rows: List[Tuple[str, str, str]] = []
    for raw in data:
        if raw is None:
            continue
        line = raw.decode("utf-8", "replace") if isinstance(raw, bytes) else raw
        m = LIST_RE.match(line)
        if not m:
            rows.append(("", "", line))
            continue
        name = m.group("name")
        # LIST quotes names that contain specials; the config needs the bare form.
        if len(name) >= 2 and name.startswith('"') and name.endswith('"'):
            name = name[1:-1].replace('\\\\', '\\').replace('\\"', '"')
        rows.append((m.group("delim"), m.group("flags"), name))
    return rows


def decode_subject(raw_headers):
    m = re.search(rb"(?im)^Subject:\s*(.*?)(?:\r?\n(?![ \t])|\r?\n\r?\n)", raw_headers)
    if not m:
        return ""
    value = m.group(1).decode("utf-8", "replace")
    parts = decode_header(value)
    return "".join(
        chunk.decode(enc or "utf-8", "replace") if isinstance(chunk, bytes) else chunk
        for chunk, enc in parts
    ).strip()


def scan_folder(srv, folder, needle, label):
    """Read-only: EXAMINE + SEARCH + PEEK at Subject headers.

    Returns (total_messages_in_folder, matching_subjects), or (None, None) when
    the folder cannot be selected.
    """
    typ, data = srv.select(imap_quote(folder), readonly=True)
    if typ != "OK":
        return None, None
    total = int(data[0]) if data and data[0] else 0
    typ, data = srv.search(None, "SUBJECT", '"%s"' % needle)
    if typ != "OK":
        die("SEARCH failed in %s: %s" % (label, data))
    uids = data[0].split()
    if not uids:
        return total, []
    typ, fetched = srv.fetch(b",".join(uids), "(BODY.PEEK[HEADER.FIELDS (SUBJECT)])")
    if typ != "OK":
        die("FETCH failed in %s: %s" % (label, fetched))
    subjects = []
    for item in fetched:
        if isinstance(item, tuple) and len(item) >= 2:
            subjects.append(decode_subject(item[1]))
    return total, subjects


def peek_recent_subjects(srv, folder, limit=5):
    """Read-only: the newest subjects in a folder, for diagnosing an empty match."""
    typ, _ = srv.select(imap_quote(folder), readonly=True)
    if typ != "OK":
        return []
    typ, data = srv.search(None, "ALL")
    uids = data[0].split() if typ == "OK" else []
    if not uids:
        return []
    typ, fetched = srv.fetch(
        b",".join(uids[-limit:]), "(BODY.PEEK[HEADER.FIELDS (SUBJECT)])"
    )
    if typ != "OK":
        return []
    return [
        decode_subject(i[1])
        for i in fetched
        if isinstance(i, tuple) and len(i) >= 2
    ]


def group_archives(subjects):
    """Map subject -> (archive name, index, total). Parts carry a '[i/N]' suffix."""
    groups = {}
    for s in subjects:
        m = re.search(r"Directory Archive:\s*(?P<name>\S+?)(?:\s*\[(?P<i>\d+)/(?P<n>\d+)\])?\s*$", s)
        if not m:
            continue
        name = m.group("name")
        idx = int(m.group("i")) if m.group("i") else 1
        total = int(m.group("n")) if m.group("n") else 1
        groups.setdefault(name, {"total": 0, "have": set()})
        groups[name]["total"] = max(groups[name]["total"], total)
        groups[name]["have"].add(idx)
    return groups


# ---------------------------------------------------------------- commands


def cmd_folders(cfg, args):
    srv = connect(cfg)
    try:
        out("connected: %s on %s" % (require(cfg, "user"), require(cfg, "host")))
        rows = list_folders(srv)
        out("")
        out("%-6s %s" % ("delim", "folder"))
        out("-" * 68)
        for delim, flags, name in rows:
            mark = "   <-- configured" if name == cfg.get("folder") else ""
            out("  %-6s %s%s" % (delim, decode_mutf7(name), mark))
        out("")
        out("%d folder(s). Set \"folder\" to one of these verbatim." % len(rows))
    finally:
        try:
            srv.logout()
        except Exception:
            pass


def cmd_scan(cfg, args):
    needle = cfg.get("subject_filter") or DEFAULT_SUBJECT_FILTER
    folder = require(cfg, "folder")
    srv = connect(cfg)
    try:
        out("filter : SUBJECT contains %r" % needle)
        out("folder : %s" % folder)
        out("")

        total, subjects = scan_folder(srv, folder, needle, folder)
        if total is None or subjects is None:
            out("[!] cannot EXAMINE %r" % folder)
            out("")
            out("available folders:")
            for delim, flags, name in list_folders(srv):
                out("    %s" % decode_mutf7(name))
            return 2

        out("[%s]" % folder)
        out("    %d message(s) total, %d matching the filter" % (total, len(subjects)))
        if subjects:
            groups = group_archives(subjects)
            out("    %d archive(s):" % len(groups))
            for name in sorted(groups):
                g = groups[name]
                have, want = sorted(g["have"]), g["total"]
                missing = [i for i in range(1, want + 1) if i not in g["have"]]
                if missing:
                    out("      %-34s %d/%d parts  MISSING %s" % (name, len(have), want, missing))
                else:
                    out("      %-34s %d/%d parts  complete" % (name, len(have), want))
        elif total:
            # Messages are there but none look like an export: either the rule is
            # wider than the filter (a test mail), or the export naming changed.
            out("    none match -- newest subjects actually in this folder:")
            for s in peek_recent_subjects(srv, folder):
                out("      %s" % (s[:78] or "(empty subject)"))

        # The rule should have MOVED them out of the inbox; anything left there
        # means the rule is not firing (or is a copy).
        if folder.upper() != "INBOX":
            in_total, in_hits = scan_folder(srv, "INBOX", needle, "INBOX")
            out("")
            out("[INBOX]  (0 expected if the rule moves rather than copies)")
            if in_total is None:
                out("    cannot EXAMINE INBOX")
            else:
                hits = in_hits or []
                out("    %d message(s), %d matching the filter" % (in_total, len(hits)))
                if hits:
                    out("    examples:")
                    for s in hits[:3]:
                        out("      %s" % s)

        out("")
        out("read-only run: nothing was fetched to disk, marked seen, or moved.")
    finally:
        try:
            srv.logout()
        except Exception:
            pass
    return 0


def cmd_not_implemented(cfg, args):
    die("'%s' is not implemented yet - only 'folders', 'scan' and 'fetch' exist so far" % args.command)


# ---------------------------------------------------------------- fetch


def find_ferry(cfg):
    """Locate ferry.py.

    Accepts the config's "ferry" (a path to ferry.py, or to the ferry.cmd shim
    which is resolved to the .py beside it), else the first `ferry`/`ferry.py` on
    PATH -- likewise resolving the shim, so no config is needed on a machine
    where ferry is already installed.
    """

    def as_py(p: Path) -> Optional[Path]:
        if p.suffix.lower() in (".cmd", ".bat"):
            p = p.with_suffix(".py")
        return p if p.is_file() else None

    explicit = cfg.get("ferry")
    if explicit:
        resolved = as_py(Path(explicit))
        if not resolved:
            die('config "ferry" does not point at a ferry.py: %s' % explicit)
        return resolved

    for name in ("ferry.py", "ferry"):
        w = shutil.which(name)
        if w:
            resolved = as_py(Path(w))
            if resolved:
                return resolved

    die('ferry.py not found; set "ferry" in the config to its full path')


def run_ferry(cfg, argv, cwd=None):
    """Invoke ferry.py with this interpreter -- calling the .py directly rather
    than the ferry.cmd shim keeps it shell-free, and is the same call on Linux."""
    ferry_py = find_ferry(cfg)
    cmd = [sys.executable, str(ferry_py)] + [str(a) for a in argv]
    r = subprocess.run(cmd, cwd=str(cwd) if cwd else None,
                       capture_output=True, text=True, encoding="utf-8", errors="replace")
    return r


def extract_attachments(raw_message):
    """(filename, bytes) for every attachment in a fetched RFC822 message.

    get_payload(decode=True) undoes the transfer encoding, so a clean trip
    reproduces the exact bytes ferry split. A mangled trip (line-ending
    conversion by an MTA/gateway) shows up later as a zip CRC failure in unpack
    rather than silently.
    """
    msg = email.message_from_bytes(raw_message, policy=email.policy.default)
    found = []
    for part in msg.walk():
        if part.get_content_maintype() == "multipart":
            continue
        filename = part.get_filename()
        if not filename:
            continue
        data = part.get_payload(decode=True)
        if data is None:
            continue
        found.append((os.path.basename(filename), data))
    return found


def fetch_messages(srv, folder, needle):
    """Read-only: every matching message's raw bytes, newest last."""
    typ, _ = srv.select(imap_quote(folder), readonly=True)
    if typ != "OK":
        die("cannot EXAMINE %r" % folder)
    typ, data = srv.search(None, "SUBJECT", '"%s"' % needle)
    if typ != "OK":
        die("SEARCH failed: %s" % data)
    uids = data[0].split()
    if not uids:
        return []
    typ, fetched = srv.fetch(b",".join(uids), "(BODY.PEEK[])")
    if typ != "OK":
        die("FETCH failed: %s" % fetched)
    return [i[1] for i in fetched if isinstance(i, tuple) and len(i) >= 2]


def plan_targets(srv, needle, folder, only):
    """Complete archives in the folder; `only` narrows to a single name."""
    _total, subjects = scan_folder(srv, folder, needle, folder)
    if subjects is None:
        die("cannot EXAMINE %r" % folder)
    if not subjects:
        out("nothing matching %r in %s" % (needle, folder))
        return {}
    groups = group_archives(subjects)
    complete = {
        n: g for n, g in groups.items()
        if not [i for i in range(1, g["total"] + 1) if i not in g["have"]]
    }
    if only:
        if only not in groups:
            die("no messages for archive %r" % only)
        if only not in complete:
            g = groups[only]
            missing = [i for i in range(1, g["total"] + 1) if i not in g["have"]]
            die("%s is incomplete (%d/%d parts, missing %s)"
                % (only, len(g["have"]), g["total"], missing))
        return {only: complete[only]}
    if not complete:
        out("no complete archive yet:")
        for n in sorted(groups):
            g = groups[n]
            missing = [i for i in range(1, g["total"] + 1) if i not in g["have"]]
            out("  %-34s %d/%d parts  MISSING %s" % (n, len(g["have"]), g["total"], missing))
        out("")
        out("re-run once the remaining part(s) arrive.")
    return complete


def fetch_archive(cfg, msgs, name, outdir):
    """Download an archive's attachments, merge, unpack, prove integrity.

    Returns the extracted .json paths, or None when the archive could not be
    assembled. ferry's merge validates the part sequence and its unpack proves
    the zip CRC, so a mail gateway that rewrote line endings is reported here
    instead of silently corrupting the heartbeats downstream.
    """
    dest = outdir / name
    dest.mkdir(parents=True, exist_ok=True)
    out("== %s ==" % name)
    for raw in msgs:
        for filename, data in extract_attachments(raw):
            if not filename.startswith(name):
                continue
            p = dest / filename
            if p.exists() and p.stat().st_size == len(data):
                out("   %-30s %d bytes (already there)" % (filename, len(data)))
                continue
            p.write_bytes(data)
            out("   %-30s %d bytes" % (filename, len(data)))

    parts = sorted(dest.glob("%s.part[0-9][0-9][0-9]*" % name)) or sorted(dest.glob(name))
    if not parts:
        out("   [!] no parts for %s" % name)
        return None

    merged = dest / name
    r = run_ferry(cfg, ["merge", "-i", str(parts[0]), "-o", str(merged)])
    if r.returncode != 0:
        out("   [!] merge failed: %s" % (r.stderr.strip() or r.stdout.strip()))
        return None

    extracted = dest / "extracted"
    r = run_ferry(cfg, ["unpack", "-i", str(merged), "-o", str(extracted)])
    if r.returncode != 0:
        out("   [X] INTEGRITY FAILURE - unpack rejected the merged archive:")
        for line in (r.stderr or r.stdout).strip().splitlines():
            out("       %s" % line)
        out("       the attachments did not survive the mail path; parts kept.")
        out("       fallback: ferry's -f text format on the RHEL6 side (base64 body).")
        return None

    jsons = sorted(extracted.rglob("*.json"))
    if not jsons:
        out("   [!] unpack produced no .json")
        return None
    out("   integrity OK - %d byte(s) merged, extracted %s"
        % (merged.stat().st_size,
           ", ".join("%s (%d bytes)" % (j.name, j.stat().st_size) for j in jsons)))
    return jsons


def cmd_fetch(cfg, args):
    needle = cfg.get("subject_filter") or DEFAULT_SUBJECT_FILTER
    folder = require(cfg, "folder")
    outdir = Path(args.dir or (Path.home() / "wakatime-ferry" / "incoming"))
    outdir.mkdir(parents=True, exist_ok=True)

    srv = connect(cfg)
    try:
        targets = plan_targets(srv, needle, folder, args.archive)
        if not targets:
            return 1
        msgs = fetch_messages(srv, folder, needle)
        for name in sorted(targets):
            fetch_archive(cfg, msgs, name, outdir)
        out("")
        out("nothing was marked seen, moved or deleted; re-running is safe.")
    finally:
        try:
            srv.logout()
        except Exception:
            pass
    return 0


# ---------------------------------------------------------------- wakapi upload


def load_wakatime_cfg():
    """api_url + api_key from ~/.wakatime.cfg.

    That file is the CLI's own config and is the only place api_url can live
    (wakatime-cli binds no env var for it; WAKATIME_API_KEY covers the key), so
    the sync side reads exactly what the CLI would use.
    """
    path = Path(os.path.expanduser(os.environ.get("WAKATIME_HOME") or "~")) / ".wakatime.cfg"
    if not path.is_file():
        die("missing %s (written by install-offline.sh / install.ps1)" % path)
    cp = configparser.ConfigParser()
    try:
        cp.read(path, encoding="utf-8")
    except configparser.Error as e:
        die("%s is not parseable: %s" % (path, e))
    if not cp.has_section("settings"):
        die("%s has no [settings] section" % path)
    url = cp.get("settings", "api_url", fallback="").strip()
    key = cp.get("settings", "api_key", fallback="").strip()
    if not url:
        die("api_url is not set in %s" % path)
    if not key:
        die("api_key is not set in %s (run :WakaTimeApiKey in nvim)" % path)
    if "127.0.0.1:1" in url:
        die("api_url is the air-gapped placeholder (%s); this machine cannot upload" % url)
    return url.rstrip("/"), key


def auth_header(key):
    """wakatime-cli sends 'Basic base64(<api_key>)' -- with no trailing colon.

    wakapi decodes whatever follows the scheme and uses it verbatim as the key
    (utils.ExtractBearerAuth), so the WakaTime convention of 'key:' would 401.
    """
    return "Basic " + base64.b64encode(key.encode("utf-8")).decode("ascii")


def post_heartbeats(api_url, key, json_path, chunk=1000):
    """POST the heartbeats; returns (http_status, {status: count}, note).

    The body is forwarded byte-for-byte when it fits one request, so nothing in
    the dump is reinterpreted; only larger dumps are re-serialised per chunk.
    """
    raw = json_path.read_bytes()
    try:
        arr = json.loads(raw)
    except ValueError as e:
        die("%s is not valid JSON: %s" % (json_path, e))
    if not isinstance(arr, list):
        die("%s is not a JSON array" % json_path)

    if len(arr) <= chunk:
        batches = [(len(arr), raw)]
    else:
        batches = [
            (len(arr[i:i + chunk]),
             json.dumps(arr[i:i + chunk], separators=(",", ":")).encode("utf-8"))
            for i in range(0, len(arr), chunk)
        ]

    url = api_url + "/users/current/heartbeats.bulk"
    tally: Dict[Any, int] = {}
    note = ""
    status = 0
    for _n, body in batches:
        req = urllib.request.Request(
            url, data=body, method="POST",
            headers={
                "Authorization": auth_header(key),
                "Content-Type": "application/json",
                "Accept": "application/json",
            },
        )
        try:
            with urllib.request.urlopen(req, timeout=60) as resp:
                status = resp.status
                payload = resp.read()
        except urllib.error.HTTPError as e:
            detail = e.read().decode("utf-8", "replace")[:200]
            if e.code == 401:
                die("wakapi rejected the api key (401). Check api_key in ~/.wakatime.cfg")
            return e.code, tally, "HTTP %d: %s" % (e.code, detail)
        except urllib.error.URLError as e:
            die("cannot reach %s: %s" % (url, e.reason))

        try:
            parsed = json.loads(payload)
        except ValueError:
            note = "unparseable response: %s" % payload.decode("utf-8", "replace")[:200]
            continue
        for item in (parsed.get("responses") or []):
            if isinstance(item, (list, tuple)) and len(item) >= 2:
                tally[item[1]] = tally.get(item[1], 0) + 1
    return status, tally, note


def ledger_path(cfg):
    return Path(cfg.get("state_file")
                or (Path.home() / "wakatime-ferry" / "state.json"))


def load_ledger(cfg):
    p = ledger_path(cfg)
    if p.is_file():
        try:
            data = json.loads(p.read_text(encoding="utf-8"))
            if isinstance(data, dict):
                data.setdefault("uploaded", {})
                return data
        except ValueError:
            pass
    return {"uploaded": {}}


def save_ledger(cfg, led):
    p = ledger_path(cfg)
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps(led, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def mark_seen(srv, folder, needle, names):
    """STORE +FLAGS (\\Seen) on the given archives' messages.

    Only a visual signal in Outlook: re-processing is prevented by the ledger,
    not by this flag, because a mail-client rule may already mark mail read on
    arrival (which is also why scan/fetch search by subject, not by UNSEEN).
    """
    if not names:
        return
    typ, _ = srv.select(imap_quote(folder), readonly=False)
    if typ != "OK":
        return
    typ, data = srv.search(None, "SUBJECT", '"%s"' % needle)
    if typ != "OK":
        return
    uids = data[0].split()
    if not uids:
        return
    typ, fetched = srv.fetch(b",".join(uids), "(BODY.PEEK[HEADER.FIELDS (SUBJECT)])")
    if typ != "OK":
        return
    seqs = []
    for item in fetched:
        if not (isinstance(item, tuple) and len(item) >= 2):
            continue
        subj = decode_subject(item[1])
        if any(subj.startswith("Directory Archive: %s" % n) for n in names):
            seqs.append(item[0].split()[0])
    if seqs:
        srv.store(b",".join(seqs), "+FLAGS", "(\\Seen)")


def cmd_sync(cfg, args):
    needle = cfg.get("subject_filter") or DEFAULT_SUBJECT_FILTER
    folder = require(cfg, "folder")
    outdir = Path(args.dir or (Path.home() / "wakatime-ferry" / "incoming"))
    outdir.mkdir(parents=True, exist_ok=True)
    api_url, key = load_wakatime_cfg()
    out("api_url: %s" % api_url)

    led = load_ledger(cfg)
    done: Dict[str, Any] = led["uploaded"]

    srv = connect(cfg)
    todo: List[str] = []
    ok: List[str] = []
    failed = 0
    try:
        targets = plan_targets(srv, needle, folder, args.archive)
        if not targets:
            return 1
        for name in sorted(targets):
            if not args.force and name in done:
                out("skip %s (already uploaded %s)" % (name, done[name].get("at", "?")))
                continue
            todo.append(name)
        if not todo:
            out("")
            out("nothing new to upload; use --force to re-upload")
            return 0

        msgs = fetch_messages(srv, folder, needle)
        for name in todo:
            jsons = fetch_archive(cfg, msgs, name, outdir)
            if jsons is None:
                failed += 1
                continue
            accepted = rejected = 0
            for j in jsons:
                status, tally, note = post_heartbeats(api_url, key, j)
                out("   POST %s -> HTTP %s  accepted=%d rejected=%d"
                    % (j.name, status, tally.get(201, 0), tally.get(400, 0)))
                if note:
                    out("        %s" % note)
                accepted += tally.get(201, 0)
                rejected += tally.get(400, 0)
            if rejected:
                out("   [!] %d heartbeat(s) rejected: usually older than"
                    " heartbeat_max_age (180d) or malformed." % rejected)
                out("   [!] %s left OUT of the ledger, so it can be retried" % name)
                failed += 1
                continue
            done[name] = {"at": datetime.now().isoformat(timespec="seconds"),
                          "heartbeats": accepted}
            save_ledger(cfg, led)
            ok.append(name)
            out("   uploaded %d heartbeat(s), recorded in the ledger" % accepted)

        if not args.keep_mails:
            mark_seen(srv, folder, needle, ok)
    finally:
        try:
            srv.logout()
        except Exception:
            pass

    out("")
    if failed:
        out("%d archive(s) failed and were not recorded" % failed)
    out("uploaded: %s" % (", ".join(ok) if ok else "nothing"))
    return 1 if failed else 0


def main():
    ap = argparse.ArgumentParser(
        prog="wakatime-fetch.py",
        description="Pull wakatime heartbeat archives out of a mailbox (ferry receiver).",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    ap.add_argument("-c", "--config", help="path to %s (default: ./%s, then script dir)" % (CONFIG_NAME, CONFIG_NAME))
    sub = ap.add_subparsers(dest="command")

    sub.add_parser("folders", help="list IMAP folders (read-only)")
    sub.add_parser("scan", help="report which archives/parts are present (read-only)")
    p_fetch = sub.add_parser("fetch", help="download a complete archive and verify it")
    p_fetch.add_argument("-a", "--archive", help="only this archive name (default: all complete ones)")
    p_fetch.add_argument("-d", "--dir", help="output dir (default: ~/wakatime-ferry/incoming)")

    p_sync = sub.add_parser("sync", help="fetch -> verify -> POST the heartbeats into wakapi")
    p_sync.add_argument("-a", "--archive", help="only this archive name (default: all complete ones)")
    p_sync.add_argument("-d", "--dir", help="output dir (default: ~/wakatime-ferry/incoming)")
    p_sync.add_argument("--force", action="store_true",
                        help="re-upload archives already recorded in the ledger")
    p_sync.add_argument("--keep-mails", action="store_true",
                        help="do not mark the uploaded messages as seen")

    args = ap.parse_args()
    if not args.command:
        ap.print_help()
        return 1

    cfg = load_config(args.config)
    fn = {
        "folders": cmd_folders,
        "scan": cmd_scan,
        "fetch": cmd_fetch,
        "sync": cmd_sync,
    }.get(args.command, cmd_not_implemented)
    return fn(cfg, args) or 0


if __name__ == "__main__":
    sys.exit(main())
