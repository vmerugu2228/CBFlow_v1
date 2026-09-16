"""
CBflow Core — Path resolution.

Single source of truth for all path calculations.
Every command module imports from here instead of re-implementing.
"""

import os
import sys

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


def require_tech_config(tech_name: str, version: str = None) -> str:
    """Hard-require a tech_config.tcl exists for this tech / version.

    Cascade (global first, PD legacy fallback):
      1. <global>/config/tech/<tech>/<ver>/tech_config.tcl  (authoritative)
      2. <core>/config/tech/<tech>/<ver>/tech_config.tcl     (pre-refactor)

    Prints a fix guide + sys.exit(1) if neither is found. Returns the first
    resolved path. Shared by library-manager and mmmc-manager preflights.
    """
    ver = version or get_flow_config_version()

    # Try global first — this is the post-refactor authoritative location.
    grot = get_global_config_root()
    if grot:
        gtc = os.path.join(grot, 'tech', tech_name, ver, 'tech_config.tcl')
        if os.path.exists(gtc):
            return gtc

    # Fallback: legacy PD-only layout (pre-refactor workareas).
    core_dir = get_cbflow_core_dir()
    tech_dir = os.path.join(core_dir, 'config', 'tech', tech_name, ver)
    tc = os.path.join(tech_dir, 'tech_config.tcl')
    if os.path.exists(tc):
        return tc

    # Neither found — enumerate what IS available and error out.
    # Prefer the global tech base (post-refactor); fall back to PD's if empty.
    tech_base = os.path.join(grot, 'tech') if grot else ''
    if not (tech_base and os.path.isdir(tech_base)):
        tech_base = os.path.join(core_dir, 'config', 'tech')

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
        # File doesn't exist — fall through to require_tech_config which will
        # produce a proper error banner listing available techs.

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

    Returns: Absolute path to <FLOW>_config.tcl
    Raises FileNotFoundError if not found.
    """
    ver = version or get_flow_config_version()
    path = os.path.join(get_config_root(), 'flow', ver, 'node_configs',
                        '{}_config.tcl'.format(flow_type))
    if not os.path.isfile(path):
        raise FileNotFoundError("Node config not found: {}".format(path))
    return path


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


def get_global_config_root() -> str:
    """Get the global config root (<global>/config) or '' if global not set up."""
    gdir = get_cbflow_global_dir()
    if not gdir:
        return ''
    root = os.path.join(gdir, 'config')
    return root if os.path.isdir(root) else ''


def get_tech_config_paths(tech_name: str, version: str = None) -> list:
    """Return the ordered list of tech_config files that should be sourced.

    Cascade:
      1. <global>/config/tech/<tech>/<ver>/tech_config.tcl  — foundry-supplied base
      2. <core>/config/tech/<tech>/<ver>/tech_pd_config.tcl — PD physical overlay

    Only files that actually exist are returned. Callers `source` them in
    order; the second file appends physical/PG/cell keys onto the tech(...)
    array populated by the first.

    During phase 1-2 (symlink shim) the two paths may resolve to the same
    file — that is expected and harmless (Tcl `set` is idempotent).
    """
    ver = version or get_flow_config_version()
    paths = []

    grot = get_global_config_root()
    if grot:
        gp = os.path.join(grot, 'tech', tech_name, ver, 'tech_config.tcl')
        if os.path.isfile(gp):
            paths.append(gp)

    try:
        crot = get_config_root()
        # Global-first: skip the PD single-file version if we already have
        # the global one (symlink-shim case). Look only for the PD overlay.
        overlay = os.path.join(crot, 'tech', tech_name, ver, 'tech_pd_config.tcl')
        if os.path.isfile(overlay):
            paths.append(overlay)
        elif not paths:
            # Legacy fallback: no global, no overlay — try the pre-refactor
            # single-file location so old workareas keep working.
            legacy = os.path.join(crot, 'tech', tech_name, ver, 'tech_config.tcl')
            if os.path.isfile(legacy):
                paths.append(legacy)
    except ValueError:
        pass

    return paths


def get_project_config_paths(project_name: str, version: str = None) -> list:
    """Return the ordered list of project_config files that should be sourced.

    Cascade:
      1. <global>/config/project/<name>/<ver>/project_config.tcl        — identity + hierarchy
      2. <core>/config/project/<name>/<ver>/project_pd_config.tcl        — PD workarea/release/lsf overlay

    Falls back to the legacy <core>/config/project/<name>/<ver>/<name>_config.tcl
    if neither of the above exists (pre-refactor workareas).
    """
    ver = version or get_flow_config_version()
    paths = []

    grot = get_global_config_root()
    if grot:
        gp = os.path.join(grot, 'project', project_name, ver, 'project_config.tcl')
        if os.path.isfile(gp):
            paths.append(gp)

    try:
        crot = get_config_root()
        overlay = os.path.join(crot, 'project', project_name, ver, 'project_pd_config.tcl')
        if os.path.isfile(overlay):
            paths.append(overlay)
        elif not paths:
            legacy = os.path.join(crot, 'project', project_name, ver,
                                  '{}_config.tcl'.format(project_name))
            if os.path.isfile(legacy):
                paths.append(legacy)
    except ValueError:
        pass

    return paths


def get_master_projects_path() -> str:
    """Return the path to master_projects.json.

    Global-first: <global>/config/master_projects.json.
    Falls back to <core>/config/master_projects.json (pre-refactor location).
    """
    grot = get_global_config_root()
    if grot:
        p = os.path.join(grot, 'master_projects.json')
        if os.path.isfile(p):
            return p
    try:
        return os.path.join(get_config_root(), 'master_projects.json')
    except ValueError:
        return ''


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
