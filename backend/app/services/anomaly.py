"""Anomaly detection for reviewer triage.

An Isolation Forest scores how unusual an application's profile looks. On its
own that score is not actionable, so a record is only flagged when a plain-
language reason can be given to the reviewer. Flags create review exceptions;
nothing is ever auto-rejected.

The forest is fitted on a synthetic baseline at start-up. In production, refit
it on a rolling window of reviewer-confirmed normal applications (`fit`).
Without scikit-learn it falls back to a robust z-score so the platform still runs.
"""
import math
import random
import statistics
from datetime import date

from .eligibility import derive_fields

FEATURES = ["age_gap", "percentage", "log_income", "name_match", "dob_match", "mismatch_count", "doc_count"]
EXPECTED_AGE = {
    "CLASS_9": 14.5, "CLASS_10": 15.5, "CLASS_11": 16.5, "CLASS_12": 17.5,
    "DIPLOMA": 18.5, "UG": 20.0, "PG": 22.5, "MPHIL": 24.5, "PHD": 27.0,
}


def build_features(profile: dict, verification: dict | None, doc_count: int, today: date | None = None) -> list[float]:
    p = derive_fields(profile, today)
    age = p.get("age")
    expected = EXPECTED_AGE.get(p.get("course_level") or "")
    age_gap = (age - expected) if (age is not None and expected is not None) else 0.0

    name_match, dob_match, mismatches = 1.0, 1.0, 0
    for check in (verification or {}).get("checks", []):
        if check.get("status") == "MISMATCH" or check.get("status") == "REVIEW":
            mismatches += 1
        comps = check.get("components") or {}
        if comps.get("name") is not None:
            name_match = min(name_match, comps["name"])
        if comps.get("dob") is not None:
            dob_match = min(dob_match, comps["dob"])

    income = p.get("annual_family_income") or 0
    return [
        float(age_gap),
        float(p.get("last_exam_percentage") if p.get("last_exam_percentage") is not None else 65.0),
        math.log10(income + 1),
        float(name_match),
        float(dob_match),
        float(mismatches),
        float(doc_count),
    ]


def explain(x: list[float]) -> list[str]:
    age_gap, pct, log_inc, name_m, dob_m, mism, docs = x
    reasons = []
    if age_gap >= 4:
        reasons.append(f"Applicant is about {age_gap:.0f} years older than is typical for this course level")
    if age_gap <= -4:
        reasons.append(f"Applicant is about {abs(age_gap):.0f} years younger than is typical for this course level")
    if pct >= 99:
        reasons.append("Reported marks are unusually high (99% or above)")
    if log_inc >= 0 and 10 ** log_inc - 1 < 1000:
        reasons.append("Family income is reported as almost nil")
    if name_m < 0.75:
        reasons.append("Name differs noticeably between sources")
    if dob_m < 0.75:
        reasons.append("Date of birth differs between sources")
    if mism >= 2:
        reasons.append(f"{int(mism)} data sources disagree with the profile")
    return reasons


def _baseline(n: int = 600, seed: int = 42) -> list[list[float]]:
    rng = random.Random(seed)
    rows = []
    for _ in range(n):
        rows.append([
            rng.gauss(0, 1.2),
            min(100.0, max(30.0, rng.gauss(68, 14))),
            rng.gauss(5.0, 0.35),
            min(1.0, max(0.6, rng.gauss(0.95, 0.05))),
            1.0 if rng.random() > 0.03 else 0.7,
            0.0 if rng.random() > 0.08 else 1.0,
            float(rng.randint(3, 5)),
        ])
    return rows


class AnomalyDetector:
    def __init__(self) -> None:
        self._model = None
        self._mu: list[float] = []
        self._sd: list[float] = []
        self.backend = "zscore"
        self.fit(_baseline())

    def fit(self, X: list[list[float]]) -> None:
        self._mu = [statistics.fmean(col) for col in zip(*X)]
        self._sd = [statistics.pstdev(col) or 1.0 for col in zip(*X)]
        try:
            from sklearn.ensemble import IsolationForest

            self._model = IsolationForest(n_estimators=150, contamination=0.03, random_state=42).fit(X)
            self.backend = "isolation_forest"
        except ImportError:
            self._model, self.backend = None, "zscore"

    def score(self, x: list[float]) -> dict:
        if self._model is not None:
            s = float(-self._model.score_samples([x])[0])  # higher = more unusual
            model_flag = bool(self._model.predict([x])[0] == -1)
        else:
            z = max(abs((v - m) / sd) for v, m, sd in zip(x, self._mu, self._sd))
            s, model_flag = min(1.0, z / 8.0), bool(z > 4.0)
        reasons = explain(x)
        flagged = bool(reasons) and (model_flag or len(reasons) >= 2)
        return {
            "score": round(s, 3),
            "flagged": flagged,
            "reasons": reasons if flagged else [],
            "backend": self.backend,
        }


_detector: AnomalyDetector | None = None


def get_detector() -> AnomalyDetector:
    global _detector
    if _detector is None:
        _detector = AnomalyDetector()
    return _detector


def assess(profile: dict, verification: dict | None, doc_count: int) -> dict:
    return get_detector().score(build_features(profile, verification, doc_count))
