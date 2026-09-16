#!/usr/bin/env python3
"""
CBFlow Graph Renderer

Renders dependency graphs as center-aligned ASCII box-and-arrow diagrams.
Main chain flows vertically centered. Parallel branches extend right
then bend 90 degrees down into branch boxes.
"""

import re as _re
from typing import List, Dict, Set, Optional

RESET  = "\033[0m"
BOLD   = "\033[1m"
GREEN  = "\033[32m"
YELLOW = "\033[33m"
CYAN   = "\033[36m"
GRAY   = "\033[90m"


def _strip_ansi(text: str) -> str:
    return _re.sub(r'\033\[[0-9;]*m', '', text)


def _center_text(text: str, width: int) -> str:
    """Center text within width, accounting for ANSI codes."""
    vis = len(_strip_ansi(text))
    pad = max(0, width - vis)
    lp = pad // 2
    rp = pad - lp
    return " " * lp + text + " " * rp


class BoxGraphRenderer:
    """Renders a center-aligned dependency graph."""

    def __init__(self, stages: List[Dict], completed: Optional[Set[str]] = None,
                 box_width: int = 30, total_width: int = 76, gap: int = 4):
        self.stages = stages
        self.completed = completed or set()
        self.bw = box_width
        self.tw = total_width       # total available width
        self.gap = gap

        self.main_stages = [s for s in stages if not s.get('is_parallel', False)]
        self.branches: Dict[str, List[Dict]] = {}
        for s in stages:
            if s.get('is_parallel', False):
                parent = s.get('dependency', '')
                self.branches.setdefault(parent, []).append(s)

        # Calculate center offset (left padding to center main boxes)
        self.offset = max(0, (self.tw - self.bw - 2) // 2)

    def _label(self, text: str, done: bool) -> str:
        icon = f"{GREEN}✓{RESET}" if done else f"{GRAY}○{RESET}"
        return f"{icon} {text}"

    def _box_center(self) -> int:
        """Center column of the box (relative to offset)."""
        return self.bw // 2 + 1

    def render(self, detail: bool = False, subnodes: dict = None,
               completed_subnodes: set = None) -> str:
        lines = []
        O = " " * self.offset  # offset to center main boxes
        bw = self.bw
        cc = self._box_center()
        subs = subnodes or {}
        comp_subs = completed_subnodes or set()

        for i, stage in enumerate(self.main_stages):
            name = stage['name']
            done = name in self.completed
            is_last = (i == len(self.main_stages) - 1)
            has_branch = name in self.branches

            c = GREEN if done else GRAY
            label = self._label(name, done)
            centered_label = _center_text(label, bw)

            # Build subnode lines for detail mode
            subnode_lines = []
            if detail and name in subs:
                for sn in subs[name]:
                    stamp_key = f"{name}_{sn}"
                    sn_done = stamp_key in comp_subs
                    sn_icon = f"{GREEN}✓{RESET}" if sn_done else f"{GRAY}○{RESET}"
                    sn_text = f"  {sn_icon} {sn}"
                    subnode_lines.append(_center_text(sn_text, bw))

            if has_branch:
                branches = self.branches[name]
                arm = self.gap
                # Column where the vertical pipe drops (from O start)
                pipe_col = bw + 2 + arm

                # Main box top
                lines.append(f"{O}{c}┌{'─' * bw}┐{RESET}")
                # Main box middle with horizontal arm: ├────┐
                lines.append(f"{O}{c}│{RESET}{centered_label}{c}├{RESET}{GRAY}{'─' * arm}┐{RESET}")
                # Main box bottom with center T + padding to pipe
                pipe_pad = pipe_col - bw - 2
                lines.append(f"{O}{c}└{'─' * cc}┬{'─' * (bw - cc - 1)}┘{RESET}{' ' * pipe_pad}{GRAY}│{RESET}")

                # Branch boxes
                for branch in branches:
                    bdone = branch['name'] in self.completed
                    bc = GREEN if bdone else YELLOW
                    blabel = self._label(branch['name'], bdone)
                    bcentered = _center_text(blabel, bw)

                    # Left: main vertical pipe, Right: branch box connected via ┴
                    left_pipe = f"{' ' * (cc + 1)}{GRAY}│{RESET}"
                    spacer = ' ' * (pipe_col - cc - 2)
                    bt_left = '─' * (arm // 2)
                    bt_right = '─' * (bw - arm // 2 - 1)

                    lines.append(f"{O}{left_pipe}{spacer}{bc}┌{bt_left}┴{bt_right}┐{RESET}")
                    lines.append(f"{O}{left_pipe}{spacer}{bc}│{RESET}{bcentered}{bc}│{RESET}")
                    lines.append(f"{O}{left_pipe}{spacer}{bc}└{'─' * bw}┘{RESET}")

                # Connector to next
                if not is_last:
                    lines.append(f"{O}{' ' * (cc + 1)}{GRAY}│{RESET}")
                    lines.append(f"{O}{' ' * (cc + 1)}{GRAY}▼{RESET}")

            else:
                # Regular box
                lines.append(f"{O}{c}┌{'─' * bw}┐{RESET}")
                lines.append(f"{O}{c}│{RESET}{centered_label}{c}│{RESET}")
                # Show subnodes in detail mode
                for sn_line in subnode_lines:
                    lines.append(f"{O}{c}│{RESET}{sn_line}{c}│{RESET}")

                if is_last:
                    lines.append(f"{O}{c}└{'─' * bw}┘{RESET}")
                else:
                    lines.append(f"{O}{c}└{'─' * cc}┬{'─' * (bw - cc - 1)}┘{RESET}")
                    lines.append(f"{O}{' ' * (cc + 1)}{GRAY}│{RESET}")
                    lines.append(f"{O}{' ' * (cc + 1)}{GRAY}▼{RESET}")

        return "\n".join(lines)


def render_graph(stages: List[Dict], completed: Optional[Set[str]] = None,
                 title: str = None, detail: bool = False,
                 subnodes: Optional[Dict[str, list]] = None) -> str:
    output = []
    if title:
        output.append("")
        output.append(_center_text(f"{BOLD}{CYAN}{title}{RESET}", 76))
        output.append(_center_text(f"{CYAN}{'═' * (len(title) + 4)}{RESET}", 76))
        output.append("")

    renderer = BoxGraphRenderer(stages, completed)
    output.append(renderer.render(detail=detail, subnodes=subnodes or {},
                                   completed_subnodes=completed or set()))

    total = len(stages)
    done = sum(1 for s in stages if s['name'] in (completed or set()))
    output.append("")
    output.append(_center_text(f"{GRAY}Stages: {done}/{total} completed{RESET}", 76))
    output.append("")
    return "\n".join(output)
