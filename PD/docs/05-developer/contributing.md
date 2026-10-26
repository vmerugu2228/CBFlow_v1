# Contributing Guide

How to contribute to CBFlow versioning system.

## Getting Started

### Fork and Clone

```bash
# Fork on GitHub first, then:
git clone https://github.com/YOUR-USERNAME/CBFlow.git
cd CBFlow/PD/core

# Add upstream
git remote add upstream https://github.com/original-org/CBFlow.git
```

### Development Setup

```bash
# Verify prerequisites
git --version      # 2.0+
python3 --version  # 3.6+
make --version     # 3.81+

# Make scripts executable
chmod +x utils/version/v2.0.0/*.py

# Test system works
make git_list_workspaces
```

## Contribution Process

### 1. Create Issue

Before coding, create GitHub issue:
- Bug report: Describe problem, steps to reproduce
- Feature request: Describe use case, proposed solution

### 2. Create Branch

```bash
# Update main
git checkout main
git pull upstream main

# Create feature branch
git checkout -b feature/description
# or
git checkout -b fix/bug-description
```

### 3. Make Changes

Follow [Code Style](#code-style) guidelines.

### 4. Test

```bash
# Manual testing
make git_create_workspace DIR=test
make git_commit_version DIR=test TYPE=patch DESC="Test"
make git_promote_version DIR=test VERSION=v1.0.0

# Verify no regressions
make list_versions DIR=gui
make git_list_releases
```

### 5. Commit

```bash
git add -A
git commit -m "type: Brief description

Detailed explanation of changes.

Fixes #123

🤖 Generated with Claude Code"
```

**Commit types:**
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation only
- `refactor`: Code restructuring
- `test`: Testing
- `chore`: Maintenance

### 6. Push and PR

```bash
git push origin feature/description
gh pr create --title "feat: Description" --body "Details"
```

## Code Style

### Python (PEP 8)

```python
# Type hints required
def method_name(param: str, flag: bool = False) -> bool:
    """Brief description.
    
    Args:
        param: Description
        flag: Description (default: False)
        
    Returns:
        True if successful
        
    Raises:
        ValueError: When invalid
    """
    pass

# Constants
MAX_VERSIONS = 100

# Classes
class MyManager:
    def __init__(self):
        pass
```

### RACE Engine

```makefile
# Clear error messages
command:
	@if [ -z "$(PARAM)" ]; then \
		echo "❌ Error: PARAM required"; \
		echo "Usage: make command PARAM=value"; \
		exit 1; \
	fi
	python3 script.py --param $(PARAM)
```

### Documentation

- Use Markdown
- Include code examples
- Keep language clear and concise
- Update all relevant docs

## Pull Request Guidelines

### PR Title

```
type: Brief description

Examples:
feat: Add config mode for releases
fix: Resolve workspace cleanup issue
docs: Update architecture documentation
```

### PR Description

```markdown
## Changes
- What was changed
- Why it was changed

## Testing
- How to test
- Test results

## Related Issues
Fixes #123
Relates to #456
```

### PR Checklist

- [ ] Code follows style guidelines
- [ ] Tests added/updated
- [ ] Documentation updated
- [ ] Commit messages follow convention
- [ ] No merge conflicts
- [ ] All checks passing

## Review Process

1. **Automated checks** - Must pass CI/CD
2. **Code review** - At least one approval required
3. **Testing** - Reviewers test changes
4. **Merge** - Squash and merge to main

## After Merge

```bash
# Update your fork
git checkout main
git pull upstream main
git push origin main

# Delete feature branch
git branch -d feature/description
git push origin --delete feature/description
```

## Issue Guidelines

### Bug Reports

```markdown
**Description**
Clear description of bug

**Steps to Reproduce**
1. Run command...
2. Expected...
3. Actual...

**Environment**
- OS: macOS 14
- Git: 2.40.0
- Python: 3.11.0

**Logs**
```
Error output here
```
```

### Feature Requests

```markdown
**Use Case**
Why is this needed?

**Proposed Solution**
How should it work?

**Alternatives**
Other approaches considered?
```

## Communication

- Be respectful and constructive
- Provide context in discussions
- Respond to feedback promptly
- Ask questions when unclear

---

**See also:**
- [Extending CBFlow](extending.md) - Add new features
- [Developer Guide](README.md) - Development overview
