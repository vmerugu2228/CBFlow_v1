"""
CBflow Core — Path resolution.

Single source of truth for all path calculations.
Every command module imports from here instead of re-implementing.
"""

import logging
import os
import stat as _stat
import sys
import tempfile

_logger = logging.getLogger('cbflow.paths')

# Default mode for new files written via atomic_write — group-readable
# matches CBflow's shared-NFS convention. Explicit constant (not a
# umask probe) so concurrent threads in the dashboard can't race and
# create world-writable files.
_CBFLOW_DEFAULT_FILE_MODE = 0o644


def atomic_write(target_path: str, content, encoding: str = 'utf-8') -> None:
    """Write ``content`` to ``target_path`` atomically via tempfile + rename.

    Guarantees the target file is either untouched (on failure) or
    contains the complete new content. Content may be str (encoded
    with ``encoding``) or bytes (written binary).

    Permission preservation: mkstemp creates the temp file with 0600
    and ``os.replace`` adopts the temp's mode — meaning atomic_write
    on a 0644 group-readable config would silently drop permissions
    to owner-only, breaking shared NFS installs. We stat the target
    (via ``os.lstat`` so we don't follow symlinks) and preserve its
    mode on an existing regular file. Symlinked targets are refused:
    atomic_write would replace the symlink itself with a regular file,
    silently de-symlinking shared release configs. Brand-new files
    get ``_CBFLOW_DEFAULT_FILE_MODE`` (0o644, group-readable).

    Crash-safety: the file is fsynced AND the parent directory is
    fsynced after replace — without the dir fsync, a hard power loss
    between os.replace and the next natural writeback can lose the
    rename on some filesystems.
    """
    target_dir = os.path.dirname(target_path) or '.'
    base = os.path.basename(target_path)
    binary = isinstance(content, (bytes, bytearray))

    # Refuse to replace a symlink — os.replace would destroy the link.
    # Use lstat so we don't follow it to the shared target. The broad
    # OSError catch below covers PermissionError and transient NFS
    # errors; only the deliberate symlink refusal escapes.
    _symlink_refusal = None
    try:
        st = os.lstat(target_path)
        if _stat.S_ISLNK(st.st_mode):
            # Build the OSError here but raise it AFTER exiting the
            # try block, so the except below only matches real stat
            # failures and not our deliberate symlink refusal.
            _symlink_refusal = OSError(
                f"atomic_write refuses to replace a symlink: {target_path} "
                f"(os.replace would destroy the symlink; edit the target or "
                f"remove the link first)")
        existing_mode = st.st_mode & 0o7777
    except OSError:
        existing_mode = _CBFLOW_DEFAULT_FILE_MODE
    if _symlink_refusal is not None:
        raise _symlink_refusal

    fd, tmp_path = tempfile.mkstemp(
        prefix=f'.{base}.',
        suffix='.cbflow_tmp',
        dir=target_dir,
    )
    # Wrap os.fdopen so a failing fdopen (invalid encoding/mode) doesn't
    # leak the mkstemp fd — the outer `except` would unlink the tempfile
    # but can't close an fd that was never bound to a file object.
    try:
        file_mode = 'wb' if binary else 'w'
        try:
            if binary:
                fh = os.fdopen(fd, file_mode)
            else:
                fh = os.fdopen(fd, file_mode, encoding=encoding)
        except Exception:
            try:
                os.close(fd)
            except OSError:
                pass
            raise
        with fh:
            fh.write(content)
            fh.flush()
            os.fsync(fh.fileno())
        # Restore the mode BEFORE replace so observers that stat the
        # new inode immediately after the rename see the correct bits
        # (not the 0600 mkstemp mode). On NFS/SMB where chmod is a
        # no-op, log a WARNING so operators notice group-readable
        # configs are silently going 0600 on next write.
        try:
            os.chmod(tmp_path, existing_mode)
        except OSError as _ce:
            _logger.warning(
                "atomic_write(%s): chmod to %o failed (%s) — file will land "
                "with the tempfile's 0600 mode. Group readers may lose access.",
                target_path, existing_mode, _ce)
        os.replace(tmp_path, target_path)
    except Exception:
        # Cleanup only reaches here if the exception fired BEFORE
        # os.replace — tmp_path is still a dangling tempfile. If
        # replace succeeded, control fell out of this try block
        # entirely, and any later failure is handled below without
        # touching tmp_path (which no longer exists at that location).
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
        raise
    # Parent-dir fsync — makes the rename durable across a hard power
    # loss. Separated from the main try so a KeyboardInterrupt / exotic
    # non-OSError raised here cannot trigger a spurious tmp_path unlink
    # on a successful write. Best-effort: wrap because non-POSIX
    # platforms and some fuse mounts don't support O_DIRECTORY.
    try:
        dir_fd = os.open(target_dir, os.O_DIRECTORY)
        try:
            os.fsync(dir_fd)
        finally:
            os.close(dir_fd)
    except OSError:
        pass

# ── Single source of truth for framework version ──
CBFLOW_VERSION = "2.0.0"

# ── Default config version — used ONLY during development/testing ──
# In production, FLOW_CONFIG_VERSION env var MUST be set
_DEFAULT_CONFIG_VERSION = "v1.0.0"


def get_cbflow_core_dir() -> str:
    """Resolve the CBflow core directory (PD/).

    Resolution order:
    1. CBFLOW_CORE_DIR environment variable (explicit, highest priority)
    2. Calculated from this file's location (PD/utils/core/paths.py → PD/)

    Raises ValueError if resolution fails — never returns empty string.
    """
    env_val = os.environ.get('CBFLOW_CORE_DIR', '')
    if env_val and os.path.isdir(env_val):
        return env_val

    # Calculate from file location: PD/utils/core/paths.py → PD/
    this_dir = os.path.dirname(os.path.abspath(__file__))
    core_dir = os.path.dirname(os.path.dirname(this_dir))

    if os.path.isdir(core_dir) and os.path.isdir(os.path.join(core_dir, 'config')):
        return core_dir

    raise ValueError(
        "Cannot resolve CBFLOW_CORE_DIR. "
        "Set the CBFLOW_CORE_DIR environment variable or run from a valid CBflow installation."
    )


def get_flow_config_version() -> str:
    """Get the flow config version string.

    Reads from FLOW_CONFIG_VERSION env var.
    Raises ValueError if not set — config version is mandatory.
    """
    version = os.environ.get('FLOW_CONFIG_VERSION', '')
    if not version:
        # Fallback to v1.0.0 ONLY during development/testing
        return 'v1.0.0'
    return version


def get_config_root() -> str:
    """Get the config root directory.

    Returns: <core_dir>/config/
    Raises ValueError if not found.
    """
    core = get_cbflow_core_dir()
    config_root = os.path.join(core, 'config')
    if not os.path.isdir(config_root):
        raise ValueError("Config root not found: {}".format(config_root))
    return config_root


def get_tech_config_path(tech_name: str, version: str = None) -> str:
    """Get path to a technology's tech_config.tcl.

    Args:
        tech_name: Technology name (e.g., 'gf_22nm', 'gf_28nm')
        version: Config version (default: from env)

    Returns: Absolute path to tech_config.tcl
    Raises FileNotFoundError if not found.
    """
    ver = version or get_flow_config_version()
    path = os.path.join(get_config_root(), 'tech', tech_name, ver, 'tech_config.tcl')
    if not os.path.isfile(path):
        raise FileNotFoundError("Tech config not found: {}".format(path))
    return path


def tech_name_from_config_path(path: str) -> str:
    """Derive the tech name from a tech_config.tcl path.

    Convention: `.../tech/<name>/<version>/tech_config.tcl`. Returns the
    `<name>` component so downstream code that still keys on a tech
    identifier (output stamps, lib_set naming) works when the user
    passes `--tech-config /path/to/tech_config.tcl` without `--tech`.
    Returns '' when the path doesn't match the convention — callers
    should fall back to a sensible default (e.g. the basename of
    lib_root) in that case.
    """
    if not path:
        return ''
    abs_path = os.path.realpath(path)
    parts = os.path.normpath(abs_path).split(os.sep)
    # Walk upward looking for ".../tech/<name>/<version>/tech_config.tcl"
    for i in range(len(parts) - 1, 1, -1):
        if parts[i] == 'tech_config.tcl' and i >= 3 and parts[i - 3] == 'tech':
            return parts[i - 2]
    return ''


def resolve_tech_config(args, version: str = None) -> tuple:
    """Return (tech_name, tech_config_path) honoring --tech-config override.

    Shared helper for library-manager / mmmc-manager so every subcommand
    resolves the same way:
      1. `args.tech_config` wins if set and the file exists — derive
         tech_name from its path, fall back to args.tech when the
         path doesn't match the convention.
      2. Otherwise resolve by name via `require_tech_config()` which
         does the standard global/PD cascade and exits on failure.
    """
    tc = getattr(args, 'tech_config', None)
    if tc and os.path.isfile(tc):
        name = tech_name_from_config_path(tc) or getattr(args, 'tech', '') or ''
        return (name, os.path.realpath(tc))
    name = (getattr(args, 'tech', None)
            or getattr(args, 'tech_node', None)
            or os.environ.get('CBFLOW_TECH_NODE', '')
            or os.environ.get('TECH_NAME', ''))
    if not name:
        # Delegate to require_tech_config so the user sees the standard
        # fix guide + available-techs list.
        require_tech_config('', version)
    return (name, require_tech_config(name, version))


def require_tech_config(tech_name: str, version: str = None) -> str:
    """Hard-require a tech_config.tcl exists for this tech / version.

    Post 2026-10-11: tech lives in a SINGLE file under global — identity
    (VT, rules, SPICE, RCX) and physical (metal stacks, cells, body bias)
    merged. PD/config/tech/ no longer exists; the former `tech_pd_config.tcl`
    content was appended into `tech_config.tcl` to keep tech data in one
    place regardless of discipline.

    Prints a fix guide + sys.exit(1) if the global tech_config is missing.
    Returns the resolved path. Shared by library-manager and mmmc-manager
    preflights.
    """
    ver = version or get_flow_config_version()

    grot = get_global_config_root()
    if grot:
        gtc = os.path.join(grot, 'tech', tech_name, ver, 'tech_config.tcl')
        if os.path.exists(gtc):
            return gtc

    # Legacy PD-side fallback — the docstring/history promises a
    # "global first, PD legacy fallback" cascade. For pre-cbflow_global
    # workareas that don't export CBFLOW_GLOBAL_DIR and don't have a
    # global/ dir, grot is '' and the fast-path above skips entirely.
    # Check PD/config/tech/<name>/<ver>/tech_config.tcl before erroring.
    core_dir = get_cbflow_core_dir()
    if core_dir:
        ptc = os.path.join(core_dir, 'config', 'tech', tech_name, ver,
                           'tech_config.tcl')
        if os.path.exists(ptc):
            return ptc

    # Not found — enumerate available techs from global (and PD fallback)
    # and error out. Prefer global's listing but include PD-side legacy
    # entries so the error banner mentions what the user actually has.
    tech_base = os.path.join(grot, 'tech') if grot else ''
    if not (tech_base and os.path.isdir(tech_base)) and core_dir:
        _pd_tech_base = os.path.join(core_dir, 'config', 'tech')
        if os.path.isdir(_pd_tech_base):
            tech_base = _pd_tech_base
    # Build the printed-expected path from whichever root the user has.
    tc = (os.path.join(grot, 'tech', tech_name, ver, 'tech_config.tcl')
          if grot else os.path.join(core_dir, 'config', 'tech',
                                    tech_name, ver, 'tech_config.tcl'))

    available = []
    if os.path.isdir(tech_base):
        for t in sorted(os.listdir(tech_base)):
            _tp = os.path.join(tech_base, t)
            if not os.path.isdir(_tp):
                continue
            for v in sorted(os.listdir(_tp)):
                _vp = os.path.join(_tp, v)
                if not os.path.isdir(_vp):
                    continue
                if os.path.exists(os.path.join(_vp, 'tech_config.tcl')):
                    available.append('{}/{}'.format(t, v))

    print('')
    print('  ═══════════════════════════════════════════════════════════')
    print('  ERROR: tech_config.tcl missing — cannot proceed')
    print('  ═══════════════════════════════════════════════════════════')
    print('    Requested: --tech {}  (version {})'.format(tech_name, ver))
    print('    Expected:  {}'.format(tc))
    print('')
    if available:
        print('    Available techs (already have tech_config.tcl):')
        for a in available:
            print('      - {}'.format(a))
    else:
        print('    No techs have a tech_config.tcl anywhere under:')
        print('      {}'.format(tech_base))
    print('')
    print('    tech_config.tcl declares tracks, VT flavors, metal stacks and')
    print('    physical cells. Downstream tools cannot know what to scan for')
    print('    or what a "complete" library set looks like without it.')
    print('')
    print('    Fix — pick one:')
    print('      (a) Create {}'.format(tc))
    print('          Start from an existing tech and edit for {}, then rerun.'.format(tech_name))
    print('      (b) Use one of the available techs above via --tech <name>')
    print('      (c) Check --version — this tool used version={}'.format(ver))
    print('')
    sys.exit(1)


def _list_available_tech_configs():
    """Return [(tech_name, version, abs_tech_config_path), ...] for every
    tech_config.tcl we can find in the install tree."""
    grot = get_global_config_root()
    tech_base = os.path.join(grot, 'tech') if grot else ''
    if not (tech_base and os.path.isdir(tech_base)):
        try:
            tech_base = os.path.join(get_config_root(), 'tech')
        except ValueError:
            return []
    out = []
    if tech_base and os.path.isdir(tech_base):
        for t in sorted(os.listdir(tech_base)):
            tp = os.path.join(tech_base, t)
            if not os.path.isdir(tp):
                continue
            for v in sorted(os.listdir(tp)):
                vp = os.path.join(tp, v)
                tc = os.path.join(vp, 'tech_config.tcl')
                if os.path.isdir(vp) and os.path.exists(tc):
                    out.append((t, v, tc))
    return out


def _diagnose_bad_tech_config_path(tc_path):
    """Print a diagnostic that names the specific issue with the user's
    --tech-config path and tells them what to do about it.

    Important production rule: a user's REAL tech_config.tcl lives on
    their filesystem (customer tech data, foundry PDK, custom overlay).
    Framework-shipped examples (gf_22nm, tsmc_7nm) are reference-only
    and almost certainly NOT what the user actually wants to point at.
    So we never say "did you mean <framework-shipped-example>" — the
    user would then point at reference data and resolve the wrong
    tech_config. Framework examples are mentioned only when labeled
    clearly as "example techs shipped with CBflow — reference only".

    Detection rules (first match wins):
      1. Literal placeholder (`/path/to/` or `<...>`) → user forgot to
         substitute the example path. Explain what tech_config.tcl is.
      2. Parent-of-parent exists on disk + is a sibling of other
         versioned dirs → user picked the wrong version of a tech they
         actually have on disk. Show the ACTUAL versions available at
         that tech dir.
      3. Parent directory exists but no tech_config.tcl in it → wrong
         filename (common: user pointed at tech_pd_config.tcl, metal
         stack file, etc.). Show what IS in that directory.
      4. Fallback → describe what tech_config.tcl is and how to find
         theirs.
    """
    print('')
    print('  ══════════════════════════════════════════════════════════════')
    print('  ERROR: --tech-config path does not exist')
    print('  ══════════════════════════════════════════════════════════════')
    print('    You supplied: {!r}'.format(tc_path))
    print('')

    available = _list_available_tech_configs()

    # ── Rule 1 — unsubstituted placeholder ─────────────────────────────
    if ('/path/to/' in tc_path or tc_path.startswith('/path/to')
            or '<' in tc_path or '>' in tc_path):
        print('    DIAGNOSIS: this is a template placeholder path, not a real')
        print('               tech_config.tcl location.')
        print('')
        print('    FIX: replace it with the ABSOLUTE path to your foundry')
        print('    tech_config.tcl on your filesystem. Common locations:')
        print('      · <your-project>/config/tech/<node>/v1.0.0/tech_config.tcl')
        print('      · <foundry-pdk-root>/<node>/cbflow/tech_config.tcl')
        print('      · ask your CAD lead where your project ships tech_config.tcl')
        print('')
        print('    tech_config.tcl holds: foundry node identity, VT patterns,')
        print('    SPICE deck, metal stacks, PG grids, standard-cell physical')
        print('    data. If you do not have one yet, start from a reference')
        print('    (see "example reference techs" below) and adapt its contents')
        print('    for your project.')
        print('')
        if available:
            print('    Example reference techs shipped with CBflow'
                  ' (reference only — do NOT run production against these):')
            for _t, _v, p in available:
                print('      - {}'.format(p))
            print('')
        return

    # ── Rule 2 — version-dir is missing but the tech-dir (grandparent)
    # does exist on disk. SAFE to suggest the real version — it's the
    # user's own filesystem. Must check parent is NOT a dir — otherwise
    # we'd mislabel a wrong-filename case as a wrong-version case. ──
    parent = os.path.dirname(tc_path)
    grandparent = os.path.dirname(parent) if parent else ''
    parent_missing = bool(parent) and not os.path.isdir(parent)
    if (parent_missing and grandparent
            and os.path.isdir(grandparent)):
        actual_versions = sorted([
            v for v in os.listdir(grandparent)
            if os.path.isdir(os.path.join(grandparent, v))
            and os.path.exists(os.path.join(grandparent, v, 'tech_config.tcl'))
        ])
        if actual_versions:
            tech_label = os.path.basename(grandparent)
            print('    DIAGNOSIS: the version you specified does not exist for '
                  'tech {!r}.'.format(tech_label))
            print('    (The tech directory does exist on your filesystem; '
                  'only the version is wrong.)')
            print('')
            print('    AVAILABLE versions for this tech on your filesystem:')
            for v in actual_versions:
                print('      - {}'.format(os.path.join(grandparent, v,
                                                       'tech_config.tcl')))
            print('')
            return

    # ── Rule 3 — parent exists but tech_config.tcl isn't in it ────────
    if parent and os.path.isdir(parent):
        print('    DIAGNOSIS: the directory exists but does not contain a file')
        print('               named `tech_config.tcl`.')
        try:
            entries = sorted(os.listdir(parent))
            tcls = [e for e in entries if e.endswith('.tcl')]
            if tcls:
                print('')
                print('    .tcl files found in that directory:')
                for e in tcls[:12]:
                    print('      - {}/{}'.format(parent, e))
            else:
                print('    No .tcl files found in that directory.')
        except OSError:
            pass
        print('')
        print('    FIX: tech_config.tcl must be named exactly that. '
              'It is NOT:')
        print('         tech_pd_config.tcl (that is a legacy PD overlay),')
        print('         <node>_config.tcl, or a metal_stack/*.tcl file.')
        print('')
        return

    # ── Fallback — describe what the file is + how to find it ─────────
    print('    DIAGNOSIS: no file at that path.')
    print('    Common causes: typo in the path, wrong case on a case-sensitive')
    print('    filesystem, missing read permission, or the file was moved.')
    print('')
    print('    What to supply: the ABSOLUTE path to the tech_config.tcl that')
    print('    describes your foundry process (node identity, VT patterns,')
    print('    metal stacks, cells, RCX data). Ask your CAD lead for its')
    print('    location on your project filesystem.')
    print('')
    if available:
        print('    Example reference techs shipped with CBflow'
              ' (reference only — do NOT run production against these):')
        for _t, _v, p in available:
            print('      - {}'.format(p))
        print('')


def preflight_tech_config_or_exit(args, tool_name: str = "library-manager") -> str:
    """Hard-gate: refuse to run if tech_config.tcl is not present.

    Applied at the argparse dispatcher for library-manager and mmmc-manager
    so EVERY subcommand — scan / check / list / status / coverage / generate
    / verify / show / validate / add-mode / etc. — is protected. Adding a
    new subcommand later cannot bypass this check.

    Tech resolution order (first non-empty wins):
        1. args.tech          (user typed --tech <name>)
        2. args.tech_node     (some subcommands use --tech-node)
        3. CBFLOW_TECH_NODE   (set by workspace create)
        4. TECH_NAME          (legacy alias, exported by start_run.py)

    Escape hatch: if the user passed --tech-config <path> AND that file
    exists, the tech resolution is bypassed (they've explicitly named the
    file to read). The file-exists check is done separately by the tool's
    own arg validator.

    On failure (no tech determinable, or tech_config.tcl missing) this
    calls sys.exit(1) via require_tech_config().

    Returns the resolved tech_config.tcl path on success.
    """
    # Escape hatch: explicit --tech-config wins over tech-name lookup.
    tc_path = getattr(args, 'tech_config', None)
    if tc_path:
        if os.path.isfile(tc_path):
            return tc_path
        # File doesn't exist — actively diagnose what's wrong with the
        # path the user supplied and show them exactly how to fix it.
        _diagnose_bad_tech_config_path(tc_path)
        sys.exit(1)

    # Resolve tech name.
    tech = (getattr(args, 'tech', None)
            or getattr(args, 'tech_node', None)
            or os.environ.get('CBFLOW_TECH_NODE', '')
            or os.environ.get('TECH_NAME', ''))
    if not tech:
        print('')
        print('  ═══════════════════════════════════════════════════════════')
        print('  ERROR: cannot run `{}` without a tech context'.format(tool_name))
        print('  ═══════════════════════════════════════════════════════════')
        print('    Every subcommand of `{}` requires tech_config.tcl to be'.format(tool_name))
        print('    present. Tell CBflow which tech to use — one of:')
        print('')
        print('      (a) pass --tech <name> on the command line')
        print('      (b) export CBFLOW_TECH_NODE=<name> (workspace create')
        print('          sets this automatically inside a run shell)')
        print('      (c) pass --tech-config <path> to point at a specific file')
        print('')
        print('    Available techs (with tech_config.tcl):')
        # Enumerate what IS available
        grot = get_global_config_root()
        tech_base = os.path.join(grot, 'tech') if grot else ''
        if not (tech_base and os.path.isdir(tech_base)):
            try:
                tech_base = os.path.join(get_config_root(), 'tech')
            except ValueError:
                tech_base = ''
        found_any = False
        if tech_base and os.path.isdir(tech_base):
            for t in sorted(os.listdir(tech_base)):
                _tp = os.path.join(tech_base, t)
                if not os.path.isdir(_tp):
                    continue
                for v in sorted(os.listdir(_tp)):
                    _vp = os.path.join(_tp, v)
                    if os.path.isdir(_vp) and os.path.exists(
                            os.path.join(_vp, 'tech_config.tcl')):
                        print('      - {}/{}'.format(t, v))
                        found_any = True
        if not found_any:
            print('      (none — no tech_config.tcl anywhere under {})'.format(tech_base or '<config>/tech/'))
        print('')
        sys.exit(1)

    # Sanitize obvious traversal patterns before joining path parts.
    if '/' in tech or '..' in tech.split(os.sep):
        print('ERROR: invalid tech name: {!r}'.format(tech))
        sys.exit(1)

    version = getattr(args, 'version', None)
    return require_tech_config(tech, version)


def get_node_config_path(flow_type: str, version: str = None) -> str:
    """Get path to a flow's node config.

    Post-Phase-5: node_configs live under the discipline root, not PD's.
    Resolution:
      1. Read flow(discipline,<flow>) from the global flow_registry.
      2. Locate the discipline root via CBFLOW_<disc>_DIR (or CBFLOW_ROOT/<disc>).
      3. Return <disc_root>/config/flow/<ver>/node_configs/<FLOW>_config.tcl.

    Raises FileNotFoundError if the resolved path does not exist.
    """
    ver = version or get_flow_config_version()

    # Determine discipline. Cheap approach: read the global registry directly
    # rather than spawning tclsh — the registry is stable Tcl but the entries
    # of interest ('flow(discipline,<FLOW>)') follow a simple `set` shape.
    #
    # _lookup_flow_discipline raises FileNotFoundError when the registry is
    # unreachable (so DFT/DV flows aren't silently misrouted to PD on broken
    # installs). Empty string means the flow is legitimately unregistered —
    # only that case falls back to 'PD'.
    try:
        _disc = _lookup_flow_discipline(flow_type, ver)
    except FileNotFoundError:
        raise FileNotFoundError(
            "flow_registry.tcl is required to resolve discipline for '{}'. "
            "Set CBFLOW_GLOBAL_DIR to a valid install or run from a workarea.".format(
                flow_type))
    disc = _disc or 'PD'

    # Discipline root
    disc_dir = _resolve_discipline_dir(disc)
    if not disc_dir:
        raise FileNotFoundError(
            f"Discipline root for '{disc}' (flow={flow_type}) not resolvable — "
            f"set CBFLOW_{disc.upper()}_DIR or CBFLOW_ROOT."
        )

    path = os.path.join(disc_dir, 'config', 'flow', ver, 'node_configs',
                        '{}_config.tcl'.format(flow_type))
    if not os.path.isfile(path):
        raise FileNotFoundError(f"Node config not found: {path} "
                                f"(discipline={disc}, flow={flow_type})")
    return path


def _lookup_flow_discipline(flow_type: str, version: str) -> str:
    """Regex-scan the global flow_registry.tcl for
    `set flow(discipline,<flow_type>) "<disc>"`.

    Returns '' ONLY when the flow is legitimately not registered. Raises
    FileNotFoundError if the registry itself is missing / unreadable:
    pre-fix every "registry missing" error collapsed to '' and callers
    silently defaulted to 'PD', so DFT/DV flows were misrouted on broken
    installs. Callers must handle the exception explicitly.
    """
    import re as _re_local
    reg = get_flow_registry_path(version)
    if not reg:
        raise FileNotFoundError(
            "flow_registry.tcl not found (version={}, CBFLOW_GLOBAL_DIR={})".format(
                version, os.environ.get('CBFLOW_GLOBAL_DIR', '')))
    try:
        with open(reg, encoding='utf-8') as fh:
            content = fh.read()
    except (OSError, UnicodeDecodeError) as e:
        raise FileNotFoundError(
            "flow_registry.tcl unreadable at {}: {}".format(reg, e))
    m = _re_local.search(
        r'set\s+flow\(discipline,' + _re_local.escape(flow_type) + r'\)\s+"?([A-Za-z_]+)"?',
        content)
    return m.group(1) if m else ''


def _resolve_discipline_dir(disc: str) -> str:
    """Find the on-disk root for a discipline (PD/DFT/DV). Order:
       1. CBFLOW_<disc>_DIR env var
       2. CBFLOW_ROOT/<disc>
       3. Sibling of CBFLOW_CORE_DIR (for PD, that's CBFLOW_CORE_DIR itself)."""
    env_val = os.environ.get(f'CBFLOW_{disc.upper()}_DIR', '')
    if env_val and os.path.isdir(env_val):
        return env_val
    root = os.environ.get('CBFLOW_ROOT', '')
    if root:
        candidate = os.path.join(root, disc)
        if os.path.isdir(candidate):
            return candidate
    try:
        core = get_cbflow_core_dir()
    except ValueError:
        return ''
    if disc == 'PD':
        return core
    candidate = os.path.join(os.path.dirname(core), disc)
    return candidate if os.path.isdir(candidate) else ''


# ══════════════════════════════════════════════════════════════════════════
# GLOBAL CONFIG LAYER (cbflow_global refactor)
#
# Introduced to host cross-discipline configs (tech identity, project
# hierarchy, master flow registry) shared by PD, DFT, and DV. During phases
# 1-3, global/config/ contains relative symlinks back to PD/config/ so every
# lookup transparently reaches today's files. Phase 3 replaces the symlinks
# with real split files; phase 4 makes global authoritative.
# ══════════════════════════════════════════════════════════════════════════

def get_cbflow_global_dir() -> str:
    """Resolve the CBflow global directory (<root>/global).

    Resolution order:
    1. CBFLOW_GLOBAL_DIR environment variable
    2. Sibling of CBFLOW_CORE_DIR (<core>/../global)

    Returns empty string if the global dir does not exist yet (framework can
    still fall back to the legacy PD-only layout). Callers must handle "".
    """
    env_val = os.environ.get('CBFLOW_GLOBAL_DIR', '')
    if env_val and os.path.isdir(env_val):
        return env_val

    try:
        core = get_cbflow_core_dir()
    except ValueError:
        return ''
    candidate = os.path.join(os.path.dirname(core), 'global')
    if os.path.isdir(candidate):
        return candidate
    return ''


def get_cbflow_releases_dir() -> str:
    """Resolve the CBflow releases directory (<global>/releases).

    Releases pin cross-discipline toolchain versions (RACE engine,
    handler framework, utilities) — the artifact is PD/DFT/DV-agnostic,
    so it lives under global/ since 2026-11-01. A legacy PD/releases/
    directory is still honored for back-compat with older installs that
    haven't been migrated.

    Returns '' if neither location exists.
    """
    gdir = get_cbflow_global_dir()
    if gdir:
        cand = os.path.join(gdir, 'releases')
        if os.path.isdir(cand):
            return cand
    try:
        core = get_cbflow_core_dir()
        cand = os.path.join(core, 'releases')
        if os.path.isdir(cand):
            return cand
    except ValueError:
        pass
    return ''


def get_global_config_root() -> str:
    """Get the global config root (<global>/config) or '' if global not set up."""
    gdir = get_cbflow_global_dir()
    if not gdir:
        return ''
    root = os.path.join(gdir, 'config')
    return root if os.path.isdir(root) else ''


def get_shared_utils_dir() -> str:
    """Return $CBFLOW_GLOBAL_DIR/utils — the shared Python/TCL tree.

    Post cbflow_global utils-refactor home for race_engine, run_cmd,
    tcl_config_parser, utilities/handler_common.tcl, utilities/launch_utils.tcl,
    and everything else that is NOT PD-discipline-specific. Returns '' when
    the global/ layer is not materialized in this checkout (sparse-checkout
    on a discipline branch); callers fall back to CBFLOW_CORE_DIR/utils.
    """
    gdir = get_cbflow_global_dir()
    if not gdir:
        return ''
    root = os.path.join(gdir, 'utils')
    return root if os.path.isdir(root) else ''


def get_tech_config_paths(tech_name: str, version: str = None) -> list:
    """Return the ordered list of tech_config files that should be sourced.

    Post-Phase-4 cascade (global authoritative):
      1. <global>/config/tech/<tech>/<ver>/tech_config.tcl   (foundry base — required)
      2. <core>/config/tech/<tech>/<ver>/tech_pd_config.tcl  (PD overlay — required)

    Only files that actually exist are returned. Callers `source` them in
    order; the second file appends physical/PG/cell keys onto the tech(...)
    array populated by the first. If either is missing the return list is
    partial; callers that need the full picture should check for both.
    """
    # Post 2026-10-11: tech is a SINGLE file in global/config/tech/<tech>/<ver>/
    # tech_config.tcl — identity + VT + rules + SPICE + RCX + metal stacks +
    # physical cells + body bias all in one place. The pre-merge split had a
    # `tech_pd_config.tcl` sibling under PD/, which contradicted the design
    # principle that tech data lives in one place regardless of discipline.
    ver = version or get_flow_config_version()
    paths = []
    grot = get_global_config_root()
    if grot:
        gp = os.path.join(grot, 'tech', tech_name, ver, 'tech_config.tcl')
        if os.path.isfile(gp):
            paths.append(gp)
    return paths


def get_project_config_paths(project_name: str, version: str = None) -> list:
    """Return the ordered list of project_config files that should be sourced.

    Post-sparse-checkout cascade:
      1. <global>/config/project/<name>/<ver>/project_config.tcl       (identity — required)
      2. <PD>/config/project/<name>/<ver>/project_pd_config.tcl        (PD overlay — if PD/ on disk)
      3. <DFT>/config/project/<name>/<ver>/project_dft_config.tcl      (DFT overlay — if DFT/ on disk)
      4. <DV>/config/project/<name>/<ver>/project_dv_config.tcl        (DV overlay — if DV/ on disk)

    All overlays set keys on the same `project(...)` Tcl array. Keys that
    appear in multiple overlays (workarea_path, race,db_path, release,path)
    MUST hold the same value in every discipline's overlay — a DFT run and
    a PD run on the same project write to the same workarea and DB. The
    overlays exist so each discipline's sparse-checkout clone can resolve
    those keys without needing another discipline's tree on disk.
    """
    ver = version or get_flow_config_version()
    paths = []

    grot = get_global_config_root()
    if grot:
        gp = os.path.join(grot, 'project', project_name, ver, 'project_config.tcl')
        if os.path.isfile(gp):
            paths.append(gp)

    # Walk each discipline's root (PD + DFT + DV) and include its project
    # overlay if present. In a full-tree clone all three attach; in a sparse
    # clone (e.g. only DV/ materialized), only the owner's overlay is on
    # disk and that's the authoritative source for workarea/release keys.
    _overlays = (
        ('CBFLOW_CORE_DIR', 'project_pd_config.tcl'),
        ('CBFLOW_DFT_DIR',  'project_dft_config.tcl'),
        ('CBFLOW_DV_DIR',   'project_dv_config.tcl'),
    )
    for env_var, filename in _overlays:
        root = os.environ.get(env_var, '').strip()
        if not root:
            continue
        overlay = os.path.join(root, 'config', 'project', project_name, ver, filename)
        if os.path.isfile(overlay):
            paths.append(overlay)

    return paths


def get_master_projects_path() -> str:
    """Return the path to master_projects.json.

    Post-Phase-4: global-only. <global>/config/master_projects.json is
    authoritative. Returns '' if the global tree is not set up (should never
    happen in a valid install — get_cbflow_global_dir() would have failed).
    """
    grot = get_global_config_root()
    if grot:
        p = os.path.join(grot, 'master_projects.json')
        if os.path.isfile(p):
            return p
    # Legacy fallback — pre-split installs kept master_projects in PD/.
    try:
        p = os.path.join(get_config_root(), 'master_projects.json')
        if os.path.isfile(p):
            return p
    except ValueError:
        pass
    return ''


# ─── Discovery helpers (list-available-X across global + PD) ─────────
#
# Rationale: a cluster of callers (mmmc_manager, workspace_cmd, test_cmd,
# config_cmd, dashboard router/app/race, project manager, library_manager)
# each used to roll their own
#     for d in os.listdir(os.path.join(get_cbflow_core_dir(), 'config/<X>')):
# which breaks post-split because <X> moved to global/. Centralize the
# discovery here so one fix covers them all.

def get_tech_search_roots() -> list:
    """Directories to scan for available technologies, highest-priority first.

    Returns a list of absolute paths. Each entry is a `<ROOT>/config/tech`
    directory. The caller walks each root and unions the child dir names.
    """
    roots = []
    grot = get_global_config_root()
    if grot:
        p = os.path.join(grot, 'tech')
        if os.path.isdir(p):
            roots.append(p)
    try:
        p = os.path.join(get_config_root(), 'tech')
        if os.path.isdir(p):
            roots.append(p)
    except ValueError:
        pass
    return roots


def list_available_techs(version: str = None) -> list:
    """List every technology directory discoverable across global/ and PD/.

    A tech is "available" if any search root has <root>/<tech>/<ver>/
    tech_config.tcl (preferred) OR just <root>/<tech>/ (looser — matches
    pre-unification installs that may not have a tech_config.tcl at the
    requested version yet).

    Returns a sorted de-duplicated list of tech names.
    """
    ver = version or get_flow_config_version()
    found = set()
    for root in get_tech_search_roots():
        try:
            entries = os.listdir(root)
        except OSError:
            continue
        for name in entries:
            if name.startswith('.'):
                continue
            d = os.path.join(root, name)
            if not os.path.isdir(d):
                continue
            # Prefer the config-present signal, but accept bare dirs too.
            if os.path.isfile(os.path.join(d, ver, 'tech_config.tcl')) \
                    or os.path.isdir(os.path.join(d, ver)) \
                    or os.path.isdir(d):
                found.add(name)
    return sorted(found)


def get_project_search_roots() -> list:
    """Directories to scan for available projects, highest-priority first.

    Returns a list of absolute paths, each a `<ROOT>/config/project` dir.
    """
    roots = []
    grot = get_global_config_root()
    if grot:
        p = os.path.join(grot, 'project')
        if os.path.isdir(p):
            roots.append(p)
    try:
        p = os.path.join(get_config_root(), 'project')
        if os.path.isdir(p):
            roots.append(p)
    except ValueError:
        pass
    return roots


def list_available_projects(version: str = None) -> list:
    """List every project directory discoverable across global/ and PD/.

    A project is "available" if any search root has <root>/<proj>/<ver>/
    project_config.tcl OR <root>/<proj>/<ver>/project_pd_config.tcl OR
    just <root>/<proj>/ (bare dir for partial scaffolds).

    Returns a sorted de-duplicated list of project names.
    """
    ver = version or get_flow_config_version()
    found = set()
    for root in get_project_search_roots():
        try:
            entries = os.listdir(root)
        except OSError:
            continue
        for name in entries:
            if name.startswith('.'):
                continue
            d = os.path.join(root, name)
            if not os.path.isdir(d):
                continue
            # Prefer configured, accept bare.
            if (os.path.isfile(os.path.join(d, ver, 'project_config.tcl'))
                    or os.path.isfile(os.path.join(
                        d, ver, 'project_pd_config.tcl'))
                    or os.path.isdir(os.path.join(d, ver))
                    or os.path.isdir(d)):
                found.add(name)
    return sorted(found)


def get_flow_registry_path(version: str = None) -> str:
    """Return the path to the global flow_registry.tcl (created in phase 3).

    Returns '' if the registry does not exist yet — callers can decide whether
    to fall back to the legacy per-discipline flow_config.tcl.
    """
    ver = version or get_flow_config_version()
    grot = get_global_config_root()
    if not grot:
        return ''
    p = os.path.join(grot, 'flow', ver, 'flow_registry.tcl')
    return p if os.path.isfile(p) else ''


# ─── Project-config cascade helpers (post-split) ─────────────────────
#
# Several Python modules (run_cmd, workspace_cmd, start_run, dashboard,
# library_manager) each used to hand-roll a 3-candidate project-config
# cascade [global/project_config.tcl, PD/project_pd_config.tcl, PD/legacy
# monolith <name>_config.tcl]. All 3 copies drifted. These helpers are
# the single source of truth.


def get_project_cfg_candidates(project_name: str, version: str = None) -> list:
    """Ordered list of project config paths to probe for a key.

    Order:
      1. global/config/project/<name>/<ver>/project_config.tcl (identity)
      2. PD/config/project/<name>/<ver>/project_pd_config.tcl  (PD overlay)
      3. PD/config/project/<name>/<ver>/<name>_config.tcl      (legacy monolith)

    Last-match-wins is the correct cascade semantic (overlays override
    identity). Entries that don't exist on disk are STILL returned —
    callers typically iterate via existence check or `concat_contents()`.
    """
    ver = version or get_flow_config_version()
    cand = []
    grot = get_global_config_root()
    if grot and project_name:
        cand.append(os.path.join(grot, 'project', project_name, ver,
                                 'project_config.tcl'))
    try:
        crot = get_config_root()
        if project_name:
            cand.append(os.path.join(crot, 'project', project_name, ver,
                                     'project_pd_config.tcl'))
            cand.append(os.path.join(crot, 'project', project_name, ver,
                                     '{}_config.tcl'.format(project_name)))
    except ValueError:
        pass
    return cand


def read_project_cfg_key(project_name: str, key: str,
                         version: str = None) -> str:
    """Read `set project(<key>) "value"` from the project cascade.

    Walks `get_project_cfg_candidates()` IN ORDER, picking LAST-match
    (so PD overlay wins over global identity). Returns '' if the key
    is unset in every file. Honors inline comments / commented-out
    `# set project(key)` lines (skipped).
    """
    import re as _re
    pat = _re.compile(
        r'^[ \t]*set\s+project\(' + _re.escape(key)
        + r'\)\s+"([^"]*)"')
    value = ''
    for cfg in get_project_cfg_candidates(project_name, version):
        if not os.path.isfile(cfg):
            continue
        try:
            with open(cfg, encoding='utf-8') as fh:
                for line in fh:
                    m = pat.match(line)
                    if m:
                        value = m.group(1).strip()
                        break  # first match within file
        except (OSError, UnicodeDecodeError):
            continue
    return value


# Extract flow_type from a run directory name. Accepts the same shapes
# the shared RUN_DIR_RE deployed in workspace_cmd / run_cmd / dashboard
# accepts (any known phase prefix: P\d+, LC\d+, MTO, BTO, R\d+, etc.).
def flow_type_from_run_dir_name(name: str) -> str:
    """Extract <FLOW> from `<PHASE>_run_<FLOW>_<RUN_NAME>`. Returns '' if
    the name doesn't match the shared run-dir shape.

    Longest-prefix match against the known flow-types list from
    global/config/flow/v1.0.0/flow_registry.tcl, so e.g.
    `P0_run_SYNTH_PNR_V2` resolves FLOW='SYNTH_PNR' and run_name='V2'
    rather than greedily absorbing uppercase run_name tokens into FLOW.
    """
    import re as _re
    _phase_rx = (r'(?:P\d+|LC\d+|LC_\d+|MTO|BTO|R\d+'
                 r'|FP|CTS|PRE|POST)')
    m = _re.match(r'^' + _phase_rx + r'_run_(.+)$', name)
    if not m:
        return ''
    tail = m.group(1)
    # Try longest-match against known flow types. Loaded lazily so
    # modules that don't need this (dashboard templates, etc.) don't
    # pay the registry-read cost at import time.
    try:
        _flow_types = _known_flow_types()
    except Exception:
        _flow_types = []
    # Longest first so SYNTH_PNR beats SYNTH when the tail starts with
    # SYNTH_PNR_<anything>.
    for ft in sorted(_flow_types, key=len, reverse=True):
        if tail == ft:
            return ft
        if tail.startswith(ft + '_'):
            return ft
    # Fallback: no registry match — use the pre-fix greedy regex but
    # cap the FLOW token at the FIRST underscore followed by an upper-
    # case-run of ≤5 chars (prevents absorbing BASELINE/V2/P1 into
    # the flow). Returns the uppercase prefix only when no known
    # flow matches, so callers at least get a predictable result.
    m2 = _re.match(r'^([A-Z][A-Z0-9]*(?:_[A-Z][A-Z0-9]*)*?)(?:_|$)', tail)
    return m2.group(1) if m2 else ''


_FLOW_TYPES_CACHE = None

def _known_flow_types() -> list:
    """Enumerate flow(types) from flow_registry.tcl. Cached per-process."""
    global _FLOW_TYPES_CACHE
    if _FLOW_TYPES_CACHE is not None:
        return _FLOW_TYPES_CACHE
    import re as _re
    out = []
    try:
        grot = get_global_config_root()
    except Exception:
        grot = ''
    if grot:
        reg = os.path.join(grot, 'flow', 'v1.0.0', 'flow_registry.tcl')
        if os.path.isfile(reg):
            try:
                with open(reg, encoding='utf-8', errors='replace') as fh:
                    body = fh.read()
                m = _re.search(
                    r'set\s+flow\(types\)\s+\{([^}]+)\}',
                    body)
                if m:
                    out = [t for t in m.group(1).split() if t]
            except OSError:
                pass
    _FLOW_TYPES_CACHE = out
    return out


def phase_from_run_dir_name(name: str) -> str:
    """Extract <PHASE> from `<PHASE>_run_<FLOW>_<RUN_NAME>`. Returns ''."""
    import re as _re
    m = _re.match(
        r'^(P\d+|LC\d+|LC_\d+|MTO|BTO|R\d+|FP|CTS|PRE|POST)_run_',
        name)
    return m.group(1) if m else ''


# Public: single-source-of-truth run-dir predicate. Replaces 4 copies
# that were spread across workspace_cmd / run_cmd / dashboard/app /
# dashboard/router with "keep in sync" comments admitting the drift risk.
def is_run_dir_name(name: str) -> bool:
    """True if `name` matches `<PHASE>_run_<FLOW>_<RUN_NAME>` where PHASE
    is a known cadence (P\\d+, LC\\d+, LC_\\d+, MTO, BTO, R\\d+, FP, CTS,
    PRE, POST) and FLOW is an uppercase token. Rejects stray user dirs
    like old_run_notes, backup_run_sim, pre_run_check."""
    import re as _re
    _re_rd = _re.compile(
        r'^(?:P\d+|LC\d+|LC_\d+|MTO|BTO|R\d+|FP|CTS|PRE|POST)_run_'
        r'[A-Z][A-Z0-9_]*(?:_|$)')
    return bool(_re_rd.match(name))
