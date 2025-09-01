## Python

- ALWAYS use `uv` for python package management (`uv add`, `uv run`, etc)
- DO NOT use old fashioned methods for package management like `poetry`, `pip` or `easy_install`.

### Standalone Python Scripts
- Python scripts are self-contained and do not require a `pyproject.toml` file.
- If a python file is intended to be executable, use a `uv` shebang at the top of the file along with a definition of dependencies. Here is an example:

```python
#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# dependencies = [
# "ffmpeg-normalize",
# ]
# ///
```

### Python Project Setup
- Make sure that there is a `pyproject.toml` file in the root directory.
- If there isn't a `pyproject.toml` file, create one using `uv init`.