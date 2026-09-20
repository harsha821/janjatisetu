"""Application state machine and the 5-stage timeline shown to the student.

Pure functions, no I/O — `workflow.py` is the DB-backed layer that calls these.

Stages (the "bridge" spans in the UI):
  APPLICATION -> VERIFICATION -> DEFICIENCY -> SANCTION -> DBT

DEFICIENCY is a detour, not a pier every application must cross: if a
correction was never raised it renders as a small "skipped" dot rather than
looking like a broken span.
"""
STAGES = ["APPLICATION", "VERIFICATION", "DEFICIENCY", "SANCTION", "DBT"]

# Which stage an application-event belongs to, keyed by the status the event records.
STAGE_OF = {
    "DRAFT": "APPLICATION",
    "SUBMITTED": "APPLICATION",
    "UNDER_VERIFICATION": "VERIFICATION",
    "DEFICIENCY": "DEFICIENCY",
    "VERIFIED": "VERIFICATION",
    "SANCTIONED": "SANCTION",
    "DBT_PAID": "DBT",
    "REJECTED": "VERIFICATION",
}

# The stage index "reached" once an application is in a given status.
_STATUS_INDEX = {
    "DRAFT": 0,
    "SUBMITTED": 1,
    "UNDER_VERIFICATION": 1,
    "DEFICIENCY": 2,
    "VERIFIED": 3,
    "SANCTIONED": 4,
    "DBT_PAID": 4,
    "REJECTED": 1,
}

# Statuses where the reached stage itself is complete, not "current".
_TERMINAL_DONE = {"DBT_PAID"}

# The formal state machine: current status -> allowed next statuses.
ALLOWED: dict[str, set[str]] = {
    "DRAFT": {"SUBMITTED"},
    "SUBMITTED": {"UNDER_VERIFICATION", "REJECTED"},
    "UNDER_VERIFICATION": {"DEFICIENCY", "VERIFIED", "REJECTED"},
    "DEFICIENCY": {"UNDER_VERIFICATION"},
    "VERIFIED": {"SANCTIONED", "REJECTED"},
    "SANCTIONED": {"DBT_PAID"},
    "DBT_PAID": set(),
    "REJECTED": set(),
}

# Statuses that count as "actively holding" a scheme for scheme-conflict checks.
ACTIVE_HOLDING = {"SUBMITTED", "UNDER_VERIFICATION", "DEFICIENCY", "VERIFIED", "SANCTIONED", "DBT_PAID"}

# Statuses in which the student may still edit the draft / attach documents.
EDITABLE = {"DRAFT", "DEFICIENCY"}


# Statuses where the whole application has concluded: an unraised deficiency stage
# is now definitely "skipped", not merely "pending", however far away it sits.
_TERMINAL = {"REJECTED", "DBT_PAID"}


def can_transition(current: str, new: str) -> bool:
    return new in ALLOWED.get(current, set())


def build_timeline(status: str, events: list[dict], ever_deficiency: bool, open_deficiency: bool) -> list[dict]:
    idx = _STATUS_INDEX.get(status, 0)
    out: list[dict] = []
    for i, stage in enumerate(STAGES):
        if status == "REJECTED":
            state = "done" if i < idx else "rejected" if i == idx else "blocked"
        elif i < idx:
            state = "done"
        elif i == idx:
            state = "done" if status in _TERMINAL_DONE else "current"
        else:
            state = "pending"

        if stage == "DEFICIENCY" and not ever_deficiency and i != idx and (i < idx or status in _TERMINAL):
            state = "skipped"

        out.append({"stage": stage, "state": state})
    return out
