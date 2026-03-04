"""Pydantic models for system/organization context — fills {curly brace} placeholders."""

from enum import Enum
from pydantic import BaseModel, Field


class ImpactLevel(str, Enum):
    LOW = "Low"
    MODERATE = "Moderate"
    HIGH = "High"


class PersonnelRole(BaseModel):
    name: str = Field(..., description="Full name with rank if applicable")
    title: str = Field(..., description="Position title")
    organization: str = Field(..., description="Organization or unit")


class SystemComponent(BaseModel):
    name: str
    description: str
    type: str = Field(..., description="e.g., Application Server, Database, AI Inference Engine")


class SystemDescription(BaseModel):
    """Organization and system metadata that fills deterministic {placeholder} tokens."""

    organization: str = Field(..., description="Organization name")
    higher_level_organization: str | None = Field(
        None, description="Parent organization, if any"
    )
    system_name: str = Field(..., description="Information system name")
    system_acronym: str = Field(..., description="System acronym")
    system_version: str = Field(default="1.0")
    emass_number: str = Field(default="TBD", description="eMASS registration number")

    confidentiality: ImpactLevel = Field(default=ImpactLevel.MODERATE)
    integrity: ImpactLevel = Field(default=ImpactLevel.MODERATE)
    availability: ImpactLevel = Field(default=ImpactLevel.LOW)

    mission: str = Field(..., description="System mission/purpose (1-2 sentences)")
    authorization_boundary: str = Field(..., description="Authorization boundary description")

    distribution_entities: str = Field(
        default="authorized personnel with a need-to-know",
        description="Who may receive the document",
    )
    distribution_office: str = Field(
        default="the Information System Security Manager (ISSM)",
        description="Office handling distribution requests",
    )

    # Signatories
    authorizing_official: PersonnelRole
    issm: PersonnelRole

    components: list[SystemComponent] = Field(default_factory=list)
