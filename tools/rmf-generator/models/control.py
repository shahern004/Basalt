"""Pydantic models for ODP (Organization-Defined Parameter) values — fills [bracket] placeholders."""

from enum import Enum
from typing import Optional

from pydantic import BaseModel, Field


class FieldSource(str, Enum):
    """Track where each value came from — deterministic or LLM-synthesized."""

    DETERMINISTIC = "deterministic"
    LLM_SYNTHESIZED = "llm_synthesized"
    USER_PROVIDED = "user_provided"


class ODPValue(BaseModel):
    """A single Organization-Defined Parameter value."""

    placeholder: str = Field(..., description="Original bracket token, e.g. '[defined frequency]'")
    value: str = Field(..., description="The replacement text")
    source: FieldSource = Field(default=FieldSource.LLM_SYNTHESIZED)


class ODPSet(BaseModel):
    """Complete set of ODP values for a control family template."""

    control_family: str = Field(..., description="e.g., MP, AC, AU")
    control_family_name: str = Field(..., description="e.g., Media Protection")
    values: list[ODPValue] = Field(..., description="All ODP replacements")

    def to_replacement_map(self) -> dict[str, str]:
        """Return mapping of [placeholder] -> replacement value."""
        return {v.placeholder: v.value for v in self.values}


class NarrativeOutput(BaseModel):
    """Constrained LLM output for ODP generation."""

    odp_values: list[ODPValue] = Field(
        ...,
        description="Organization-Defined Parameter values tailored to the system context",
    )
    reasoning: Optional[str] = Field(
        None,
        description="Brief explanation of choices for audit trail",
    )
