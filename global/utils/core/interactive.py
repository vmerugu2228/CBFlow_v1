"""
CBflow Core — Interactive REPL helper.

Shared machinery for tools that:
  · Require a tech context (tech_config.tcl must exist)
  · Have a dispatch table of subcommands
  · Should drop into a prompt-driven REPL when invoked with no subcommand

Currently used by:
  · mmmc-manager  (PD/utils/commands/mmmc_manager_cmd.py)
  · library-manager (PD/utils/commands/library_manager_cmd.py)

Any future tool that fits the same shape (dispatcher + tech gate + optional
interactive mode) should import `run_repl` from here instead of re-implementing.
"""

import os
import shlex
import logging

from core.paths import (
    get_global_config_root,
    get_config_root,
    require_tech_config,
)

_logger = logging.getLogger('cbflow.interactive')


def list_available_techs() -> list:
    """Return tech names that have a tech_config.tcl on disk.

    Delegates to `core.paths.list_available_techs` so programmatic callers
    and the REPL always see the same list. The previous divergent copy
    silently differed on bare-dir tolerance — a tech scaffold with no
    tech_config.tcl was visible to one and invisible to the other.
    """
    from .paths import list_available_techs as _shared
    out = _shared()
    # REPL additionally requires a tech_config.tcl to actually source,
    # so filter to those entries that have one in at least one root.
    kept = []
    roots = []
    grot = get_global_config_root()
    if grot:
        roots.append(os.path.join(grot, 'tech'))
    try:
        roots.append(os.path.join(get_config_root(), 'tech'))
    except Exception:
        pass
    for name in out:
        for root in roots:
            tp = os.path.join(root, name)
            if not os.path.isdir(tp):
                continue
            for v in os.listdir(tp):
                vp = os.path.join(tp, v)
                if os.path.isdir(vp) and os.path.isfile(
                        os.path.join(vp, 'tech_config.tcl')):
                    kept.append(name)
                    break
            if kept and kept[-1] == name:
                break
    return kept


def _run_handler(handler, args) -> int:
    """Invoke a subcommand handler, catching the usual exceptions.

    Returns the handler's exit code (0 on success). SystemExit is caught
    so a sub-handler that calls sys.exit doesn't kill the REPL — its exit
    code is returned but the caller stays in the loop.
    """
    try:
        rc = handler(args)
        return rc if isinstance(rc, int) else 0
    except KeyboardInterrupt:
        print("\nAborted.")
        return 1
    except PermissionError as e:
        _logger.error("Permission denied: %s", e)
        return 1
    except FileNotFoundError as e:
        _logger.error("File not found: %s", e)
        return 1
    except SystemExit as e:
        return int(e.code) if e.code else 0
    except Exception as e:
        _logger.error("Error: %s: %s", type(e).__name__, e)
        return 1


def run_repl(top_parser,
             dispatch: dict,
             tool_name: str,
             logger: logging.Logger = None,
             extra_help_lines: list = None,
             post_tech_hook=None) -> int:
    """Interactive REPL for a subcommand-dispatching tool.

    Flow:
      1. Resolve tech from CBFLOW_TECH_NODE / TECH_NAME or prompt the user.
         Only techs with tech_config.tcl on disk are accepted.
      2. Call require_tech_config() to warm the resolver cache and confirm.
      3. Loop: prompt → argparse-parse → dispatch handler → repeat.
      4. Exit on `exit` / `quit` / `q` / Ctrl-D. `help` lists commands.
         `tech <name>` switches context mid-session.

    The REPL survives argparse errors (bad flag, --help, unknown command)
    and per-handler exceptions — the loop only breaks on explicit exit.

    post_tech_hook: optional callable(tech_config_path) invoked after
      the REPL resolves the current tech (startup) and after every
      `tech <name>` switch mid-session. Library-manager uses this to
      install tech(process_corners) via `_apply_tech_corners` — without
      it, subcommands dispatched from inside the REPL silently fall
      back to the compiled 5-corner default (ss/tt/ff/sf/fs), so a
      tech that ships `fff` corners gets its libs miscategorized.
      Hook exceptions are logged at WARNING (not DEBUG) so a silent
      failure doesn't reintroduce the exact miscategorization bug the
      hook was added to prevent. A non-callable hook is rejected at
      entry — passing a non-callable is a programmer error, not a
      runtime condition.
    """
    log = logger or _logger
    if post_tech_hook is not None and not callable(post_tech_hook):
        raise TypeError(
            f"run_repl: post_tech_hook must be callable, got "
            f"{type(post_tech_hook).__name__}")

    def _invoke_post_tech_hook(tc_path):
        if post_tech_hook is None:
            return
        try:
            post_tech_hook(tc_path)
        except Exception as _e:
            log.warning(
                "post_tech_hook failed for %r: %s — downstream subcommands "
                "may miscategorize libs or fall back to default corners",
                tc_path, _e)

    print()
    print('  ═══════════════════════════════════════════════════════════')
    print('  {} — interactive mode'.format(tool_name))
    print('  ═══════════════════════════════════════════════════════════')
    print('  Type `help` for commands, `exit` to leave.')
    print()

    # ── Tech context ─────────────────────────────────────────────────
    tech = os.environ.get('CBFLOW_TECH_NODE', '') or os.environ.get('TECH_NAME', '')
    avail = list_available_techs()
    if not tech:
        if not avail:
            print('  (no techs with tech_config.tcl found — nothing to preflight against)')
            print('  Exiting.')
            return 1
        print('  Available techs: {}'.format(', '.join(avail)))
        while not tech:
            try:
                answer = input('  Tech name (or exit): ').strip()
            except (EOFError, KeyboardInterrupt):
                print()
                return 0
            if answer.lower() in ('exit', 'quit', 'q'):
                print('  bye.')
                return 0
            if answer not in avail:
                print('  Unknown tech: {!r}. Choose one of: {}'.format(
                      answer, ', '.join(avail)))
                continue
            tech = answer
    os.environ['CBFLOW_TECH_NODE'] = tech

    _tc_path = require_tech_config(tech)
    _invoke_post_tech_hook(_tc_path)
    print('  Tech context set: {}'.format(tech))
    print()
    print('  Commands: {}'.format(', '.join(sorted(dispatch.keys()))))
    print('            help, exit, tech <name>')
    print()

    prompt = '  {} [{}] > '.format(tool_name, tech)
    while True:
        try:
            line = input(prompt).strip()
        except (EOFError, KeyboardInterrupt):
            print()
            print('  bye.')
            return 0

        if not line:
            continue
        low = line.lower()
        if low in ('exit', 'quit', 'q'):
            print('  bye.')
            return 0
        if low in ('help', '?', 'h'):
            print('  Commands:')
            for name in sorted(dispatch.keys()):
                print('    · {}'.format(name))
            print('    · tech <name>  — switch tech context')
            print('    · help         — this list')
            print('    · exit         — leave the REPL')
            if extra_help_lines:
                for extra in extra_help_lines:
                    print(extra)
            print('  Every subcommand accepts the same flags as the non-interactive form.')
            print('  Run `<command> --help` for details.')
            continue
        if low.startswith('tech '):
            new_tech = line.split(None, 1)[1].strip()
            if new_tech not in list_available_techs():
                print('  Unknown tech: {!r}'.format(new_tech))
                continue
            tech = new_tech
            os.environ['CBFLOW_TECH_NODE'] = tech
            _tc_path = require_tech_config(tech)
            _invoke_post_tech_hook(_tc_path)
            prompt = '  {} [{}] > '.format(tool_name, tech)
            print('  Tech context: {}'.format(tech))
            continue

        # Parse the line as if it were argv
        try:
            argv = shlex.split(line)
        except ValueError as e:
            print('  parse error: {}'.format(e))
            continue

        try:
            sub_args = top_parser.parse_args(argv)
        except SystemExit:
            # argparse already printed the error; stay in the REPL
            continue

        handler = dispatch.get(sub_args.command)
        if not handler:
            print('  unknown command: {}'.format(sub_args.command))
            print('  try `help` for the list.')
            continue

        _run_handler(handler, sub_args)
