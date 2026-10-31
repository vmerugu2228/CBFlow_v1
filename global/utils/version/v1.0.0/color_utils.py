#!/usr/bin/env python3
"""
Color and Icon Utilities for Flow Management System

Provides colorized output and enhanced icons for better user readability
"""

import os
import sys
from typing import Optional

class Colors:
    """ANSI color codes for terminal output"""

    # Basic colors
    BLACK = ''
    RED = ''
    GREEN = ''
    YELLOW = ''
    BLUE = ''
    MAGENTA = ''
    CYAN = ''
    WHITE = ''

    # Bright colors
    BRIGHT_BLACK = ''
    BRIGHT_RED = ''
    BRIGHT_GREEN = ''
    BRIGHT_YELLOW = ''
    BRIGHT_BLUE = ''
    BRIGHT_MAGENTA = ''
    BRIGHT_CYAN = ''
    BRIGHT_WHITE = ''

    # Background colors
    BG_BLACK = ''
    BG_RED = ''
    BG_GREEN = ''
    BG_YELLOW = ''
    BG_BLUE = ''
    BG_MAGENTA = ''
    BG_CYAN = ''
    BG_WHITE = ''

    # Styles
    BOLD = ''
    DIM = ''
    ITALIC = ''
    UNDERLINE = ''
    BLINK = ''
    REVERSE = ''
    STRIKETHROUGH = ''

    # Reset
    RESET = ''
    END = ''

class Icons:
    """Plain text icons for terminal output"""

    # Status icons - use plain text
    SUCCESS = '[OK]'
    ERROR = '[ERROR]'
    WARNING = '[WARN]'
    INFO = '[INFO]'
    QUESTION = '[?]'

    # Process icons
    GEAR = ''
    ROCKET = ''
    WRENCH = ''
    HAMMER = ''
    TOOLBOX = ''

    # File/folder icons
    FOLDER = ''
    FILE = ''
    PACKAGE = ''
    DOCUMENT = ''
    BOOK = ''
    SCROLL = ''

    # Version control icons
    TAG = ''
    BRANCH = ''
    COMMIT = ''
    MERGE = ''
    CURRENT = '[*]'

    # Flow icons
    FLOW = ''
    ARROW_RIGHT = '->'
    ARROW_DOWN = 'v'
    ARROW_UP = '^'
    CHECKMARK = '[+]'
    CROSS = '[-]'

    # Special icons
    STAR = '*'
    LIGHTNING = ''
    FIRE = ''
    HEART = ''
    DIAMOND = ''
    CROWN = ''

    # Progress icons
    HOURGLASS = ''
    CLOCK = ''
    STOPWATCH = ''
    TIMER = ''

    # Communication icons
    EMAIL = ''
    BELL = ''
    LOUDSPEAKER = ''
    MEGAPHONE = ''

class ColorPrinter:
    """Enhanced printer with color and icon support"""

    def __init__(self, enable_colors: bool = None):
        """Initialize with color support detection"""
        if enable_colors is None:
            # Auto-detect color support
            self.colors_enabled = self._supports_colors()
        else:
            self.colors_enabled = enable_colors

    def _supports_colors(self) -> bool:
        """Check if terminal supports colors"""
        # Check if output is a terminal
        if not hasattr(sys.stdout, 'isatty') or not sys.stdout.isatty():
            return False

        # Check environment variables
        term = os.environ.get('TERM', '').lower()
        if 'color' in term or term in ['xterm', 'xterm-256color', 'screen', 'tmux']:
            return True

        # Check if we're in a known color-supporting environment
        if os.environ.get('COLORTERM') or os.environ.get('FORCE_COLOR'):
            return True

        return False

    def colorize(self, text: str, color: str = '', style: str = '') -> str:
        """Apply color and style to text"""
        if not self.colors_enabled:
            return text

        prefix = f"{style}{color}" if style or color else ""
        suffix = Colors.RESET if prefix else ""
        return f"{prefix}{text}{suffix}"

    def print_success(self, message: str, icon: str = Icons.SUCCESS):
        """Print success message in green"""
        colored_msg = self.colorize(f"{icon} {message}", Colors.BRIGHT_GREEN, Colors.BOLD)
        print(colored_msg)

    def print_error(self, message: str, icon: str = Icons.ERROR):
        """Print error message in red"""
        colored_msg = self.colorize(f"{icon} {message}", Colors.BRIGHT_RED, Colors.BOLD)
        print(colored_msg, file=sys.stderr)

    def print_warning(self, message: str, icon: str = Icons.WARNING):
        """Print warning message in yellow"""
        colored_msg = self.colorize(f"{icon} {message}", Colors.BRIGHT_YELLOW, Colors.BOLD)
        print(colored_msg)

    def print_info(self, message: str, icon: str = Icons.INFO):
        """Print info message in blue"""
        colored_msg = self.colorize(f"{icon} {message}", Colors.BRIGHT_BLUE)
        print(colored_msg)

    def print_header(self, message: str, icon: str = Icons.STAR):
        """Print header with border"""
        border = "=" * (len(message) + 4)
        header_color = Colors.BRIGHT_CYAN

        print(self.colorize(border, header_color, Colors.BOLD))
        print(self.colorize(f"{icon} {message} {icon}", header_color, Colors.BOLD))
        print(self.colorize(border, header_color, Colors.BOLD))

    def print_section(self, message: str, icon: str = Icons.ARROW_RIGHT):
        """Print section header"""
        colored_msg = self.colorize(f"\n{icon} {message}", Colors.BRIGHT_MAGENTA, Colors.BOLD)
        print(colored_msg)

    def print_item(self, message: str, icon: str = Icons.CHECKMARK, indent: int = 2):
        """Print list item with indentation"""
        spaces = " " * indent
        colored_msg = self.colorize(f"{spaces}{icon} {message}", Colors.WHITE)
        print(colored_msg)

    def print_version(self, version: str, is_current: bool = False):
        """Print version with appropriate styling"""
        if is_current:
            icon = Icons.CURRENT
            color = Colors.BRIGHT_GREEN
            style = Colors.BOLD
            suffix = " CURRENT"
        else:
            icon = Icons.TAG
            color = Colors.BRIGHT_CYAN
            style = ""
            suffix = ""

        colored_msg = self.colorize(f"   {icon} {version}{suffix}", color, style)
        print(colored_msg)

    def print_component(self, name: str, icon: str = Icons.FOLDER):
        """Print component name with styling"""
        colored_msg = self.colorize(f"\n{icon} {name.upper()} Components:", Colors.BRIGHT_YELLOW, Colors.BOLD)
        print(colored_msg)

    def print_release(self, version: str, description: str = "", milestone: str = ""):
        """Print release information with styling"""
        icon = Icons.PACKAGE
        colored_version = self.colorize(f"{icon} {version}", Colors.BRIGHT_GREEN, Colors.BOLD)
        print(colored_version)

        if milestone:
            milestone_msg = self.colorize(f"   Milestone: {milestone}", Colors.BRIGHT_MAGENTA)
            print(milestone_msg)

        if description:
            desc_msg = self.colorize(f"   {description}", Colors.WHITE)
            print(desc_msg)
        else:
            status_msg = self.colorize(f"   Available", Colors.BRIGHT_BLUE)
            print(status_msg)

# Global instance for easy use
printer = ColorPrinter()

# Convenience functions
def print_success(message: str, icon: str = Icons.SUCCESS):
    printer.print_success(message, icon)

def print_error(message: str, icon: str = Icons.ERROR):
    printer.print_error(message, icon)

def print_warning(message: str, icon: str = Icons.WARNING):
    printer.print_warning(message, icon)

def print_info(message: str, icon: str = Icons.INFO):
    printer.print_info(message, icon)

def print_header(message: str, icon: str = Icons.STAR):
    printer.print_header(message, icon)

def print_section(message: str, icon: str = Icons.ARROW_RIGHT):
    printer.print_section(message, icon)

def colorize(text: str, color: str = '', style: str = '') -> str:
    return printer.colorize(text, color, style)

if __name__ == "__main__":
    # Demo of color and icon capabilities
    print_header("Flow Management System Color Demo")

    print_section("Status Messages")
    print_success("Operation completed successfully!")
    print_error("Something went wrong!")
    print_warning("This is a warning message")
    print_info("Here's some useful information")

    print_section("Version Information")
    printer.print_version("v1.0.0", is_current=True)
    printer.print_version("v0.9.0", is_current=False)

    print_section("Components")
    printer.print_component("CONFIG", Icons.GEAR)
    printer.print_item("technology: v1.0.0")
    printer.print_item("project: v1.0.0")

    print_section("Releases")
    printer.print_release("v2.1.0", "Major feature release", "MILESTONE_DEMO")
    printer.print_release("v2.0.0", "Stable release")