"""Record linkage and fuzzy matching.

Used in two places:
  * per student: cross-checking a profile against UIDAI / APAAR / e-District
  * population level: matching enrolled ST students (UDISE+/APAAR) against
    scholarship records (NSP/OTR, SFMP, NOS) for coverage-gap detection

Design notes
  * Indian names vary by transliteration (Sunita/Sunitha), token order
    (Munda Ramesh / Ramesh Munda) and dropped middle names. Names are
    compared after light phonetic folding, order-insensitively, and a
    name that is a token-subset of the other scores high.
  * A definite APAAR ID match wins outright.
  * Uncertain scores (POSSIBLE) go to human review, never to auto-decision.
  * Blocking keeps population matching near-linear instead of O(n*m).
"""
import re
import unicodedata
from collections import defaultdict
from dataclasses import dataclass, field
from datetime import date

try:  # optional speed-up
    from rapidfuzz import fuzz

    def _ratio(a: str, b: str) -> float:
        return fuzz.ratio(a, b) / 100.0

except ImportError:  # pragma: no cover - exercised when rapidfuzz is absent
    from difflib import SequenceMatcher

    def _ratio(a: str, b: str) -> float:
        return SequenceMatcher(None, a, b).ratio()


MATCH_T = 0.85
REVIEW_T = 0.65

_HONORIFICS = {"mr", "mrs", "ms", "shri", "smt", "sri", "kumari", "kum", "dr", "late", "master"}
_PHONETIC = [
    (r"(?<=[a-z])h", ""),  # aspirates: bh, dh, gh, kh, th, ph, sh -> b, d, g, k, t, p, s
    (r"f", "p"),
    (r"w", "v"),
    (r"z", "j"),
    (r"ee|ii", "i"),
    (r"oo|uu", "u"),
    (r"aa", "a"),
    (r"(.)\1+", r"\1"),  # collapse doubled letters
]


def _tokens(name: str) -> list[str]:
    s = unicodedata.normalize("NFKD", name or "").lower()
    s = re.sub(r"[^\w\s]", " ", s)
    return [t for t in s.split() if t not in _HONORIFICS]


def phonetic(token: str) -> str:
    out = token
    for pat, rep in _PHONETIC:
        out = re.sub(pat, rep, out)
    return out.rstrip("aeh") or out  # Sunita/Sunitha/Sunit -> same stem


def name_similarity(a: str | None, b: str | None) -> float | None:
    if not a or not b:
        return None
    ta = [phonetic(t) for t in _tokens(a) if len(t) > 1]
    tb = [phonetic(t) for t in _tokens(b) if len(t) > 1]
    if not ta or not tb:
        return None
    base = _ratio(" ".join(sorted(ta)), " ".join(sorted(tb)))
    small, big = (ta, tb) if len(ta) <= len(tb) else (tb, ta)
    covered = all(any(_ratio(x, y) >= 0.85 for y in big) for x in small)
    if covered and len(small) >= 2:
        return max(base, 0.92)
    if covered:
        return max(base, 0.85)
    return base


def _as_date(v) -> date | None:
    if isinstance(v, date):
        return v
    if isinstance(v, str) and v:
        try:
            return date.fromisoformat(v)
        except ValueError:
            return None
    return None


def dob_similarity(a, b) -> float | None:
    da, db = _as_date(a), _as_date(b)
    if not da or not db:
        return None
    if da == db:
        return 1.0
    if da.year == db.year and (da.month, da.day) == (db.day, db.month):
        return 0.7  # day/month swapped, a common entry error
    if da.year == db.year and da.month == db.month:
        return 0.4
    return 0.0


def _text_similarity(a, b) -> float | None:
    if not a or not b:
        return None
    return _ratio(str(a).lower().strip(), str(b).lower().strip())


@dataclass
class MatchResult:
    score: float
    decision: str  # MATCH | POSSIBLE | NO_MATCH
    reason: str
    components: dict = field(default_factory=dict)


_WEIGHTS = {"name": 0.50, "dob": 0.30, "institution": 0.10, "district": 0.10}


def match_score(a: dict, b: dict) -> MatchResult:
    """Compare two person records (keys: name, dob, gender, apaar_id, institution_name, district)."""
    ida, idb = (a.get("apaar_id") or "").strip(), (b.get("apaar_id") or "").strip()
    if ida and idb and ida == idb:
        return MatchResult(1.0, "MATCH", "EXACT_ID", {"apaar_id": 1.0})

    comps = {
        "name": name_similarity(a.get("name"), b.get("name")),
        "dob": dob_similarity(a.get("dob"), b.get("dob")),
        "institution": _text_similarity(a.get("institution_name"), b.get("institution_name")),
        "district": _text_similarity(a.get("district"), b.get("district")),
    }
    avail = {k: v for k, v in comps.items() if v is not None}
    if "name" not in avail:
        return MatchResult(0.0, "NO_MATCH", "NO_NAME", comps)

    total_w = sum(_WEIGHTS[k] for k in avail)
    score = sum(_WEIGHTS[k] * v for k, v in avail.items()) / total_w

    ga, gb = (a.get("gender") or "").upper()[:1], (b.get("gender") or "").upper()[:1]
    if ga and gb and ga != gb:
        score -= 0.15
    if ida and idb and ida != idb:
        score -= 0.20
    score = max(0.0, min(1.0, score))

    decision = "MATCH" if score >= MATCH_T else "POSSIBLE" if score >= REVIEW_T else "NO_MATCH"
    return MatchResult(round(score, 3), decision, "FUZZY", {k: (round(v, 3) if v is not None else None) for k, v in comps.items()})


def _name_key(name: str | None) -> str:
    toks = sorted((phonetic(t) for t in _tokens(name or "") if len(t) > 1), key=len, reverse=True)
    return toks[0][:3] if toks else ""


class Matcher:
    """Indexes a pool of records so each lookup only scores plausible candidates."""

    def __init__(self, pool: list[dict]):
        self.by_apaar: dict[str, list[dict]] = defaultdict(list)
        self.by_dob: dict[str, list[dict]] = defaultdict(list)
        self.by_state_name: dict[tuple, list[dict]] = defaultdict(list)
        for r in pool:
            if r.get("apaar_id"):
                self.by_apaar[r["apaar_id"]].append(r)
            d = _as_date(r.get("dob"))
            if d:
                self.by_dob[d.isoformat()].append(r)
            self.by_state_name[((r.get("state") or "").lower(), _name_key(r.get("name")))].append(r)

    def candidates(self, rec: dict) -> list[dict]:
        seen: dict[int, dict] = {}
        d = _as_date(rec.get("dob"))
        blocks = [
            self.by_apaar.get(rec.get("apaar_id") or "", []),
            self.by_dob.get(d.isoformat(), []) if d else [],
            self.by_state_name.get(((rec.get("state") or "").lower(), _name_key(rec.get("name"))), []),
        ]
        for block in blocks:
            for r in block:
                seen[id(r)] = r
        return list(seen.values())

    def best(self, rec: dict) -> tuple[dict | None, MatchResult]:
        best_rec, best_res = None, MatchResult(0.0, "NO_MATCH", "NO_CANDIDATE")
        for cand in self.candidates(rec):
            res = match_score(rec, cand)
            if res.score > best_res.score:
                best_rec, best_res = cand, res
        return best_rec, best_res
