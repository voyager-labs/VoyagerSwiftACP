"""base

Revision ID: 52b6d89590e3
Revises:
Create Date: 2025-09-17 11:53:13.665248+00:00

"""

from __future__ import annotations

from typing import Sequence, Union

# revision identifiers, used by Alembic.
revision: str = "52b6d89590e3"
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:  # pragma: no cover - empty baseline
    """Upgrade schema."""
    pass


def downgrade() -> None:  # pragma: no cover - empty baseline
    """Downgrade schema."""
    pass
