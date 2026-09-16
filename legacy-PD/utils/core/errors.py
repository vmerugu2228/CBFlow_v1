"""
CBflow Core — Error types and formatting.

All CBflow-specific exceptions in one place.
"""


class CBflowError(Exception):
    """Base exception for all CBflow errors."""
    pass


class ConfigError(CBflowError):
    """Missing or invalid configuration."""
    def __init__(self, key, source='config'):
        self.key = key
        self.source = source
        super().__init__(
            "Required {} variable not set: {}. "
            "Check your project_config, tech_config, or user_config.".format(source, key)
        )


class MissingInputError(CBflowError):
    """Required input file or variable not provided."""
    def __init__(self, input_name, expected_in='user_config.tcl'):
        self.input_name = input_name
        super().__init__(
            "Required input not provided: {}. Set it in {}".format(input_name, expected_in)
        )


class ToolError(CBflowError):
    """EDA tool configuration or invocation error."""
    def __init__(self, tool_name, detail):
        self.tool_name = tool_name
        super().__init__("Tool error ({}): {}".format(tool_name, detail))


class RunDirectoryError(CBflowError):
    """Not in a valid run directory."""
    def __init__(self, path=None):
        path = path or 'current directory'
        super().__init__(
            "Not in a valid CBflow run directory: {}. "
            "Navigate to a run directory first.".format(path)
        )
