"""CLI: render a re-tagged .docx template with system context and ODP values.

Loads the re-tagged Jinja2 template (from retag_template.py), builds a context
dict from notional_system.yaml + hardcoded ODP values, renders via docxtpl,
and writes the filled document.

Usage:
    cd basalt-stack/tools/rmf-generator
    python fill_template.py [--template PATH] [--output PATH] [--system-yaml PATH]
"""

import argparse
import re
import sys
from pathlib import Path

import yaml
from docxtpl import DocxTemplate
from jinja2.exceptions import UndefinedError
from pydantic import ValidationError

# Add this directory to path for model imports
sys.path.insert(0, str(Path(__file__).resolve().parent))

from models.system import SystemDescription


# ─── Jinja2 Sanitization ────────────────────────────────────────────────────
# Defense-in-depth: strip Jinja2 metacharacters from context values before
# rendering. Prevents SSTI if LLM-generated values (B3) contain template syntax.

_JINJA2_META = re.compile(r"\{\{|\}\}|\{%|%\}|\{#|#\}")


def sanitize_template_value(value: str) -> str:
    """Strip Jinja2 metacharacters from a value before template rendering."""
    return _JINJA2_META.sub("", value)


# ─── Hardcoded ODP Values (realistic for MERIDIAN demo) ──────────────────────
# In B3, these will be LLM-generated via vLLM structured output.
# For B1, they are static values tailored to the DGIA/MERIDIAN scenario.

HARDCODED_ODP_VALUES: dict[str, str] = {
    "odp_defined_frequency": "annually",
    "odp_defined_events": (
        "significant changes to the system or operating environment"
    ),
    "odp_defined_roles": (
        "Information System Security Manager (ISSM) and system administrators"
    ),
    "odp_defined_official": "the Information System Security Manager (ISSM)",
    "odp_types_digital_nondigital_media": (
        "removable hard drives, USB flash drives, CDs, DVDs, and printed documents"
    ),
    "odp_types_media_exempted_marking": (
        "media used solely within the secure facility perimeter"
    ),
    "odp_controlled_areas": "DGIA Secure Computing Facility (SCF), Server Room B",
    "odp_types_system_media": (
        "all digital media containing CUI or classified information"
    ),
    "odp_automated_mechanisms": (
        "automated access control lists and physical access logging systems"
    ),
    "odp_controls": (
        "encryption of data at rest using FIPS 140-3 validated modules "
        "and tamper-evident packaging"
    ),
    "odp_system_media": "all digital and non-digital media containing system data",
    "odp_systems_components": (
        "all workstations, servers, and portable computing devices "
        "within the authorization boundary"
    ),
    "odp_circumstances": (
        "return from travel, receipt from external sources, "
        "or upon discovery of potential compromise"
    ),
    "odp_sanitization_techniques": (
        "NSA/CSS EPL-listed degaussers for magnetic media; "
        "NIST SP 800-88 Clear/Purge procedures for solid-state media"
    ),
    "odp_media_downgrading_process": (
        "the DGIA Media Downgrading Standard Operating Procedure (SOP), "
        "reviewed annually"
    ),
    "odp_media_requiring_downgrading": (
        "any media transitioning from classified to unclassified "
        "handling environments"
    ),
    "odp_conditions": (
        "confirmed or suspected compromise of media contents"
    ),
    "odp_restrict_prohibit": "restrict",
    "odp_policy_level": "organization-level",
    "odp_remote_purge_conditions": (
        "remotely, under confirmed or suspected compromise conditions"
    ),
}


# ─── Context Assembly ────────────────────────────────────────────────────────

def load_system_yaml(path: Path) -> SystemDescription:
    """Load and validate system description from YAML file."""
    with open(path) as f:
        try:
            data = yaml.safe_load(f)
        except yaml.YAMLError as exc:
            print(f"ERROR: Invalid YAML in {path}: {exc}", file=sys.stderr)
            sys.exit(1)

    try:
        return SystemDescription(**data)
    except ValidationError as exc:
        print(f"ERROR: System YAML validation failed:\n{exc}", file=sys.stderr)
        sys.exit(1)


def build_context(system: SystemDescription) -> dict[str, str]:
    """Build the template rendering context from system metadata + ODPs.

    Returns a flat dict where keys match the Jinja2 variable names in the
    re-tagged template (e.g., 'organization', 'odp_defined_frequency').
    All values are sanitized to strip Jinja2 metacharacters.
    """
    ctx: dict[str, str] = {
        # System metadata — fills {{ curly_brace }} variables
        "organization": system.organization,
        "system_name": system.system_name,
        "system_acronym": system.system_acronym,
        "higher_level_organization": (
            system.higher_level_organization or system.organization
        ),
        "distribution_entities": system.distribution_entities,
        "distribution_office": system.distribution_office,
        "confidentiality": system.confidentiality.value,
        "integrity": system.integrity.value,
        "availability": system.availability.value,
        "ao_name": system.authorizing_official.name,
        "ao_title": system.authorizing_official.title,
        "issm_name": system.issm.name,
        "issm_title": system.issm.title,
        "logo": "",  # MVP: skip image insertion
    }

    # ODP values — fills {{ odp_* }} variables
    ctx.update(HARDCODED_ODP_VALUES)

    # Sanitize all values (defense-in-depth for B3 when LLM values enter)
    return {k: sanitize_template_value(v) for k, v in ctx.items()}


# ─── CLI ──────────────────────────────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Render a re-tagged .docx template with system context and ODP values"
    )
    parser.add_argument(
        "--template",
        type=Path,
        default=Path("templates/MP.docx"),
        help="Re-tagged template path (default: templates/MP.docx)",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("output/MP-filled.docx"),
        help="Output document path (default: output/MP-filled.docx)",
    )
    parser.add_argument(
        "--system-yaml",
        type=Path,
        default=Path("data/notional_system.yaml"),
        help="System description YAML (default: data/notional_system.yaml)",
    )
    args = parser.parse_args()

    if not args.template.exists():
        print(f"ERROR: Template not found: {args.template}", file=sys.stderr)
        print(
            "Run retag_template.py first to generate the re-tagged template.",
            file=sys.stderr,
        )
        sys.exit(1)

    if not args.system_yaml.exists():
        print(f"ERROR: System YAML not found: {args.system_yaml}", file=sys.stderr)
        sys.exit(1)

    # Load system context
    print(f"Loading system context: {args.system_yaml}")
    system = load_system_yaml(args.system_yaml)

    # Build rendering context
    context = build_context(system)
    print(f"Context: {len(context)} variables")

    # Render template
    print(f"Rendering template:    {args.template}")
    tpl = DocxTemplate(str(args.template))
    try:
        tpl.render(context)
    except UndefinedError as exc:
        print(
            f"ERROR: Template variable missing from context: {exc}\n"
            "Check that all Jinja2 variables in the template have matching "
            "entries in the context dict.",
            file=sys.stderr,
        )
        sys.exit(1)

    # Save output
    args.output.parent.mkdir(parents=True, exist_ok=True)
    tpl.save(str(args.output))
    print(f"Output saved to:       {args.output}")

    # Summary
    print()
    print("System metadata filled:")
    print(f"  Organization:  {context['organization']}")
    print(f"  System:        {context['system_name']} ({context['system_acronym']})")
    print(f"  Impact levels: C={context['confidentiality']}, "
          f"I={context['integrity']}, A={context['availability']}")
    print(f"  AO:            {context['ao_name']}")
    print(f"  ISSM:          {context['issm_name']}")
    print(f"  ODP values:    {sum(1 for k in context if k.startswith('odp_'))} filled")


if __name__ == "__main__":
    main()
