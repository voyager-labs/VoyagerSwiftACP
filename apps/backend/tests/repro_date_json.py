import sys
from pathlib import Path
repo_root = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(repo_root / "apps" / "backend" / "src"))

from core.search import ConditionBuilder
from core.metadata import SYSTEM_PROPERTY_REGISTRY

builder = ConditionBuilder()
# recording_date is a date type but not indexed (uses JSON)
clause, params = builder.build_clause("recording_date", "eq", "2024-01-01")
print(f"Clause: {clause}")
print(f"Params: {params}")

# content_creation_date is indexed (uses DB)
clause_db, params_db = builder.build_clause("content_creation_date", "eq", "2024-01-01")
print(f"DB Clause: {clause_db}")
