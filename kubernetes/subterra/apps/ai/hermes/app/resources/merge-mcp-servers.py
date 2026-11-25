"""Add the deployment's MCP defaults to an existing Hermes profile."""

from collections.abc import MutableMapping
from pathlib import Path
import os
import sys
from tempfile import NamedTemporaryFile

from ruamel.yaml import YAML


profile_path, defaults_path = map(Path, sys.argv[1:])
yaml = YAML()
yaml.preserve_quotes = True

profile = yaml.load(profile_path)
if profile is None:
    profile = {}
if not isinstance(profile, MutableMapping):
    raise ValueError(f"Expected mapping in {profile_path}")

servers = profile.get("mcp_servers")
if servers is None:
    servers = profile["mcp_servers"] = {}
if not isinstance(servers, MutableMapping):
    raise ValueError(f"Expected mcp_servers mapping in {profile_path}")

defaults = yaml.load(defaults_path)["mcp_servers"]
missing = {name: config for name, config in defaults.items() if name not in servers}
if missing:
    servers.update(missing)
    with NamedTemporaryFile(mode="w", encoding="utf-8", dir=profile_path.parent, delete=False) as output:
        temporary_path = Path(output.name)
        try:
            yaml.dump(profile, output)
            output.flush()
            os.replace(temporary_path, profile_path)
        finally:
            temporary_path.unlink(missing_ok=True)
