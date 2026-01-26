import sys
from pathlib import Path

repo_root = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(repo_root / "apps" / "backend" / "src"))

from core.search import ConditionBuilder

builder = ConditionBuilder()
# contact_keywords is a string_list
clause, params = builder.build_clause("contact_keywords", "all", ["alpha", "alpha"])
print(f"Clause: {clause}")
print(f"Params: {params}")
