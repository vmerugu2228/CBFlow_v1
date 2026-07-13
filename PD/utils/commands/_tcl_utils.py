"""Shared Tcl-parsing utilities used across cbflow's Python commands.

Both `checklist_cmd.cmd_add_check` and `run_cmd.load_custom_nodes_from_runtime_config`
need to walk a Tcl `array set NAME { ... }` block and find the balanced
closing brace. Owning that walker in one module (rather than reaching
into `checklist_cmd`'s private symbol from `run_cmd`) means:
  - a rename or refactor is caught by both consumers at import-time;
  - future consumers (waiver_cmd, mandatory_files editors) can import
    from here without adding cross-module dependencies.
"""


def find_balanced_close(text: str, start: int, open_depth: int = 1) -> int:
    """Find the index of the balanced closing `}` starting from `start`
    with `open_depth` already open. Returns -1 on unbalanced.

    Word-boundary tokenizer. Handles:
      - `#` comments to end-of-line, ONLY at word start.
      - `"..."` quoted words, ONLY at word start. A bare `"` inside a
        bareword or braced-word body is treated as a literal char.
      - `\\` escapes anywhere.
      - `{...}` braced blocks — `{` opens a new nesting (word start
        preserved for the block body); `}` closes.
      - `[...]` command substitution — next token inside a `[` is a
        new command, so `#` at `[<ws>#` would begin a comment.
      - DOS `\\r\\n` line endings.

    A "word start" is TRUE at BOF, after whitespace, after `\\n`/`\\r`,
    after `;`, after `[`, after `{`, and after `"` closes (Tcl syntax:
    the space between two words resets word-start, but so does the
    closing `"` — the next non-space char begins a new word). Getting
    this right is what makes `"key" "value with }"` parse correctly:
    the opening `"` of the value comes after whitespace, and its
    contents (including `}`) are consumed as string body.
    """
    depth = open_depth
    i = start
    n = len(text)
    at_word_start = True
    while i < n and depth > 0:
        c = text[i]
        if c == ' ' or c == '\t':
            # Whitespace SEPARATES words — after any run of whitespace,
            # the next non-space char begins a new word. Without this
            # `"key" "value with }"` fails: `"key"` closes and sets
            # at_word_start=False; if the intervening space doesn't
            # reset, the value `"` is treated as literal and its `}`
            # decrements depth.
            at_word_start = True
            i += 1
            continue
        if c == '\n' or c == '\r':
            at_word_start = True
            i += 1
            continue
        if c == ';':
            at_word_start = True
            i += 1
            continue
        # Comment: `#` at a word-start position → skip to EOL.
        if c == '#' and at_word_start:
            while i < n and text[i] not in ('\n', '\r'):
                if text[i] == '\\' and i + 1 < n:
                    i += 2
                    continue
                i += 1
            continue
        # Quoted-word: `"` at a word-start position → skip to matching `"`.
        if c == '"' and at_word_start:
            i += 1
            while i < n and text[i] != '"':
                if text[i] == '\\' and i + 1 < n:
                    i += 2
                    continue
                i += 1
            if i < n:
                i += 1  # consume closing `"`
            at_word_start = False
            continue
        if c == '\\' and i + 1 < n:
            i += 2
            at_word_start = False
            continue
        if c == '{':
            depth += 1
            at_word_start = True
            i += 1
            continue
        if c == '}':
            depth -= 1
            if depth == 0:
                return i
            at_word_start = False
            i += 1
            continue
        if c == '[':
            at_word_start = True
            i += 1
            continue
        if c == ']':
            at_word_start = False
            i += 1
            continue
        # Any other char: we're inside a bareword.
        at_word_start = False
        i += 1
    return -1


def tcl_quote(s) -> str:
    """Escape a string for splicing into a Tcl `"..."` literal.

    Escapes `\\`, `"`, `$`, and `[`. Inside a `"..."` string, `$var`
    performs variable substitution and `[cmd]` executes an embedded
    command AT SOURCE TIME — both are code-injection sinks when a
    checklist / waiver / config-editor CLI splices raw user input into
    the file. Escaping neutralizes all four.
    """
    if s is None:
        return ''
    return (str(s)
            .replace('\\', '\\\\')
            .replace('"',  '\\"')
            .replace('$',  '\\$')
            .replace('[',  '\\['))
