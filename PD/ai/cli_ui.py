#!/usr/bin/env python3
"""
CBflow SmartGenie — Terminal UI (Claude Code style).

Provides colored, formatted CLI output with spinners, streaming,
and markdown-like rendering for the AI agent.
"""

import os
import readline
import sys
import time
import threading

# ═══════════════════════════════════════════════════════════════════════════════
# READLINE SETUP (arrow keys, history, editing)
# ═══════════════════════════════════════════════════════════════════════════════

HISTORY_FILE = os.path.expanduser('~/.cbflow_smartgenie_history')

def _init_readline():
    """Set up readline for arrow keys, history, and tab completion."""
    # Load history from previous sessions
    try:
        readline.read_history_file(HISTORY_FILE)
    except FileNotFoundError:
        pass
    readline.set_history_length(500)
    # Enable emacs-style editing (Ctrl+A, Ctrl+E, Ctrl+K, etc.)
    if sys.platform == 'darwin':
        readline.parse_and_bind('bind ^I rl_complete')
    else:
        readline.parse_and_bind('tab: complete')

def _save_history():
    """Save history on exit."""
    try:
        readline.write_history_file(HISTORY_FILE)
    except Exception:
        pass

_init_readline()
import atexit
atexit.register(_save_history)

# ═══════════════════════════════════════════════════════════════════════════════
# COLORS
# ═══════════════════════════════════════════════════════════════════════════════

NO_COLOR = os.environ.get('NO_COLOR', '') != ''

def _c(code: str, text: str) -> str:
    if NO_COLOR: return text
    return f"\033[{code}m{text}\033[0m"

def bold(t): return _c("1", t)
def dim(t): return _c("2", t)
def italic(t): return _c("3", t)
def blue(t): return _c("34", t)
def cyan(t): return _c("36", t)
def green(t): return _c("32", t)
def yellow(t): return _c("33", t)
def red(t): return _c("31", t)
def magenta(t): return _c("35", t)
def gray(t): return _c("90", t)
def white(t): return _c("97", t)
def bg_blue(t): return _c("44", t)
def bg_green(t): return _c("42", t)
def bg_red(t): return _c("41", t)
def bg_yellow(t): return _c("43", t)


# ═══════════════════════════════════════════════════════════════════════════════
# SPINNER
# ═══════════════════════════════════════════════════════════════════════════════

class Spinner:
    """Animated spinner for long operations."""
    FRAMES = ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏']

    def __init__(self, message="Thinking"):
        self.message = message
        self._running = False
        self._thread = None

    def start(self):
        self._running = True
        self._thread = threading.Thread(target=self._spin, daemon=True)
        self._thread.start()

    def stop(self, final=""):
        self._running = False
        if self._thread:
            self._thread.join(timeout=1)
        sys.stderr.write(f"\r\033[K")  # Clear line
        if final:
            sys.stderr.write(f"  {final}\n")
        sys.stderr.flush()

    def _spin(self):
        i = 0
        while self._running:
            frame = self.FRAMES[i % len(self.FRAMES)]
            sys.stderr.write(f"\r  {cyan(frame)} {dim(self.message)}...")
            sys.stderr.flush()
            time.sleep(0.1)
            i += 1


# ═══════════════════════════════════════════════════════════════════════════════
# OUTPUT FORMATTING
# ═══════════════════════════════════════════════════════════════════════════════

def banner(model: str, server: str = None, username: str = None, workspace: str = ""):
    """Print the SmartGenie startup banner."""
    w = 62
    print()
    print(f"  {blue('┌' + '─' * w + '┐')}")
    print(f"  {blue('│')}{bold('   ██████╗██████╗ ███████╗██╗      ██████╗ ██╗    ██╗       ')}{blue('│')}")
    print(f"  {blue('│')}{bold('  ██╔════╝██╔══██╗██╔════╝██║     ██╔═══██╗██║    ██║       ')}{blue('│')}")
    print(f"  {blue('│')}{bold('  ██║     ██████╔╝█████╗  ██║     ██║   ██║██║ █╗ ██║       ')}{blue('│')}")
    print(f"  {blue('│')}{bold('  ██║     ██╔══██╗██╔══╝  ██║     ██║   ██║██║███╗██║       ')}{blue('│')}")
    print(f"  {blue('│')}{bold('  ╚██████╗██████╔╝██║     ███████╗╚██████╔╝╚███╔███╔╝       ')}{blue('│')}")
    print(f"  {blue('│')}{bold('   ╚═════╝╚═════╝ ╚═╝     ╚══════╝ ╚═════╝  ╚══╝╚══╝       ')}{blue('│')}")
    print(f"  {blue('│')}{cyan('  SmartGenie AI Agent')}{gray(' — 100% Private                      ')}{blue('│')}")
    print(f"  {blue('├' + '─' * w + '┤')}")
    if server:
        print(f"  {blue('│')}  {dim('Server:')}  {green(server):<53}{blue('│')}")
        print(f"  {blue('│')}  {dim('User:')}    {cyan(username or 'anonymous'):<53}{blue('│')}")
        print(f"  {blue('│')}  {dim('Mode:')}    {yellow('Enterprise (shared knowledge)'):<53}{blue('│')}")
    else:
        print(f"  {blue('│')}  {dim('Model:')}   {green(model):<53}{blue('│')}")
        print(f"  {blue('│')}  {dim('Mode:')}    {cyan('Local (standalone)'):<53}{blue('│')}")
    print(f"  {blue('│')}  {dim('Privacy:')} {bold('Data NEVER leaves your network'):<53}{blue('│')}")
    print(f"  {blue('└' + '─' * w + '┘')}")
    print()


def prompt_input() -> str:
    """Styled user input prompt."""
    try:
        return input(f"  {bold(cyan('❯'))} ").strip()
    except (KeyboardInterrupt, EOFError):
        return ""


def agent_text(text: str):
    """Print agent response with markdown-like formatting."""
    lines = text.split('\n')
    for line in lines:
        # Headers
        if line.startswith('### '):
            print(f"  {bold(line[4:])}")
        elif line.startswith('## '):
            print(f"  {bold(cyan(line[3:]))}")
        elif line.startswith('# '):
            print(f"  {bold(blue(line[2:]))}")
        # Code blocks
        elif line.strip().startswith('```'):
            print(f"  {dim(line)}")
        # Bullet points
        elif line.strip().startswith('- ') or line.strip().startswith('* '):
            print(f"  {cyan('●')} {line.strip()[2:]}")
        # Table rows
        elif '|' in line and line.strip().startswith('|'):
            print(f"  {dim(line)}")
        # Numbered lists
        elif len(line) > 2 and line.strip()[:2].replace('.', '').isdigit():
            print(f"  {yellow(line.strip()[:2])}{line.strip()[2:]}")
        # Empty lines
        elif not line.strip():
            print()
        # Normal text
        else:
            # Inline code
            import re
            formatted = re.sub(r'`([^`]+)`', lambda m: cyan(m.group(1)), line)
            print(f"  {formatted}")


def tool_start(name: str, args_str: str = ""):
    """Print tool invocation."""
    icon = {
        'bash': '⚡',
        'read_file': '📄',
        'write_file': '✏️',
        'query_db': '🔍',
        'search_kb': '📚',
        'learn': '💡',
    }.get(name, '🔧')
    truncated = args_str[:80] + ('...' if len(args_str) > 80 else '')
    print(f"  {icon} {yellow(name)} {dim(truncated)}")


def tool_result(text: str, max_lines: int = 8):
    """Print tool result (abbreviated)."""
    lines = text.strip().split('\n')
    shown = lines[:max_lines]
    for line in shown:
        # Color errors red, warnings yellow, info blue
        if 'ERROR' in line or 'FAIL' in line:
            print(f"    {red(line[:120])}")
        elif 'WARNING' in line or 'WARN' in line:
            print(f"    {yellow(line[:120])}")
        elif 'PASS' in line or 'DONE' in line or 'SUCCESS' in line:
            print(f"    {green(line[:120])}")
        else:
            print(f"    {dim(line[:120])}")
    if len(lines) > max_lines:
        print(f"    {dim(f'... ({len(lines) - max_lines} more lines)')}")
    print()


def status_badge(text: str, style: str = "info"):
    """Print a colored status badge."""
    if style == "pass":
        print(f"  {bg_green(bold(f' {text} '))}")
    elif style == "fail":
        print(f"  {bg_red(bold(f' {text} '))}")
    elif style == "warn":
        print(f"  {bg_yellow(bold(f' {text} '))}")
    else:
        print(f"  {blue(bold(f'[{text}]'))}")


def separator():
    """Print a dim separator line."""
    print(f"  {dim('─' * 60)}")


def turn_indicator(turn: int, elapsed: float = 0):
    """Print turn number indicator."""
    if elapsed > 0:
        print(f"  {dim(f'Turn {turn}')} {dim(f'({elapsed:.1f}s)')}")
    else:
        print(f"  {dim(f'Turn {turn}')}")


def goodbye():
    """Print session end message."""
    print()
    separator()
    print(f"  {dim('Session ended. All data stayed local.')}")
    print(f"  {dim('Tip: type')} {cyan('cbflow smartgenie')} {dim('to start again')}")
    print()


def error(msg: str):
    """Print error message."""
    print(f"  {red('✗')} {red(msg)}")


def success(msg: str):
    """Print success message."""
    print(f"  {green('✓')} {msg}")


def info(msg: str):
    """Print info message."""
    print(f"  {blue('ℹ')} {dim(msg)}")


def help_text():
    """Print help for interactive mode."""
    print()
    print(f"  {bold('SmartGenie Commands:')}")
    print(f"    {cyan('/help')}      Show this help")
    print(f"    {cyan('/status')}    Show workspace status")
    print(f"    {cyan('/flows')}     List available flows")
    print(f"    {cyan('/search')} {dim('<query>')}  Search knowledge base")
    print(f"    {cyan('/stats')}     Knowledge base stats")
    print(f"    {cyan('/clear')}     Clear conversation")
    print(f"    {cyan('exit')}       End session")
    print()
