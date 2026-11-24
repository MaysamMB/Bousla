"""Validate a Bousla course dataset.

Usage:
    python src/ai/validate_data.py data/courses/database-systems

Checks (errors fail the run with exit code 1):
- Required files exist and contain valid JSON.
- IDs are unique; option IDs are unique within each question.
- Every bilingual field has non-empty "ar" and "en" text, and Arabic prompts
  and concept names actually contain Arabic letters.
- Concept prerequisites reference existing concepts, never themselves, and
  contain no cycles.
- Questions reference existing concepts, have at least two options, and do not
  embed the correct answer (answer keys live in answer_keys.json only).
- Every question has exactly one answer key that matches one of its options,
  and there are no keys for unknown questions.
- Questions have an integer version >= 1.
- Resources reference existing concepts, use an allowed type and language,
  and have a url (link/video), a storage_path (file) or a description
  (activity).
- Provenance source and status are allowed values; a source_material_id
  refers to an entry in the optional materials.json; the optional "edited"
  flag is a boolean; an optional "rejection_reason" is an allowed value and
  only appears on rejected items.
- course.json has an owner_id field (null allowed in seed files).

Warnings (reported, do not fail):
- Concepts with fewer than MIN_QUESTIONS_PER_CONCEPT questions; the engine
  reports "insufficient evidence" below that number of responses.
- Items whose provenance status is not "approved" (not yet human-reviewed).

Standard library only.
"""
from __future__ import annotations

import json
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

REQUIRED_FILES = ("course.json", "concepts.json", "questions.json", "answer_keys.json", "resources.json")
OPTIONAL_MATERIALS_FILE = "materials.json"
LANGUAGES = ("ar", "en")
ALLOWED_STATUS = {"pending_review", "approved", "rejected"}
ALLOWED_SOURCE = {"ai_draft", "instructor", "team"}
ALLOWED_MATERIAL_STATUS = {"processing", "ready_for_review", "failed"}
ALLOWED_REJECTION_REASONS = {"incorrect", "unclear", "translation", "duplicate", "off_topic", "other"}
RESOURCE_TYPES = {"activity", "link", "video", "file"}
RESOURCE_LANGUAGES = {"ar", "en", "both"}
MIN_QUESTIONS_PER_CONCEPT = 2
FORBIDDEN_QUESTION_FIELDS = {"correct_option_id", "answer", "correct"}
ARABIC_LETTER = re.compile(r"[؀-ۿ]")


@dataclass
class Report:
    errors: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)

    def error(self, msg: str) -> None:
        self.errors.append(msg)

    def warn(self, msg: str) -> None:
        self.warnings.append(msg)

    @property
    def ok(self) -> bool:
        return not self.errors


def _load(path: Path, report: Report):
    if not path.is_file():
        report.error(f"{path.name}: file is missing")
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        report.error(f"{path.name}: invalid JSON ({exc})")
        return None


def _check_bilingual(value, where: str, report: Report, require_arabic: bool = False) -> None:
    if not isinstance(value, dict):
        report.error(f"{where}: expected an object with 'ar' and 'en'")
        return
    for lang in LANGUAGES:
        text = value.get(lang)
        if not isinstance(text, str) or not text.strip():
            report.error(f"{where}: missing or empty '{lang}' text")
    ar = value.get("ar")
    if require_arabic and isinstance(ar, str) and ar.strip() and not ARABIC_LETTER.search(ar):
        report.error(f"{where}: 'ar' text contains no Arabic letters")


def _check_provenance(item: dict, where: str, report: Report, material_ids: set[str]) -> bool:
    """Returns True if the item is approved."""
    prov = item.get("provenance")
    if not isinstance(prov, dict):
        report.error(f"{where}: missing provenance")
        return False
    source = prov.get("source")
    if source not in ALLOWED_SOURCE:
        report.error(f"{where}: provenance.source '{source}' not in {sorted(ALLOWED_SOURCE)}")
    material = prov.get("source_material_id")
    if material is not None and material not in material_ids:
        report.error(f"{where}: unknown source_material_id '{material}'")
    if "edited" in prov and not isinstance(prov["edited"], bool):
        report.error(f"{where}: provenance.edited must be true or false")
    status = prov.get("status")
    reason = prov.get("rejection_reason")
    if reason is not None:
        if reason not in ALLOWED_REJECTION_REASONS:
            report.error(f"{where}: provenance.rejection_reason '{reason}' not in {sorted(ALLOWED_REJECTION_REASONS)}")
        elif status != "rejected":
            report.error(f"{where}: provenance.rejection_reason is only allowed on rejected items")
    if status not in ALLOWED_STATUS:
        report.error(f"{where}: provenance.status '{status}' not in {sorted(ALLOWED_STATUS)}")
        return False
    return status == "approved"


def _unique_ids(items: list, label: str, report: Report) -> set[str]:
    seen: set[str] = set()
    for i, item in enumerate(items):
        iid = item.get("id") if isinstance(item, dict) else None
        if not isinstance(iid, str) or not iid:
            report.error(f"{label}[{i}]: missing 'id'")
            continue
        if iid in seen:
            report.error(f"{label}: duplicate id '{iid}'")
        seen.add(iid)
    return seen


def _find_cycle(graph: dict[str, list[str]]) -> list[str] | None:
    WHITE, GREY, BLACK = 0, 1, 2
    color = {node: WHITE for node in graph}
    stack: list[str] = []

    def visit(node: str) -> list[str] | None:
        color[node] = GREY
        stack.append(node)
        for nxt in graph.get(node, []):
            if nxt not in color:
                continue
            if color[nxt] == GREY:
                return stack[stack.index(nxt):] + [nxt]
            if color[nxt] == WHITE:
                found = visit(nxt)
                if found:
                    return found
        stack.pop()
        color[node] = BLACK
        return None

    for node in graph:
        if color[node] == WHITE:
            found = visit(node)
            if found:
                return found
    return None


def validate_course(course_dir: Path) -> Report:
    report = Report()
    data = {name: _load(course_dir / name, report) for name in REQUIRED_FILES}
    if not report.ok:
        return report

    course, concepts, questions, keys, resources = (data[n] for n in REQUIRED_FILES)

    for name, value, expected in (
        ("course.json", course, dict),
        ("concepts.json", concepts, list),
        ("questions.json", questions, list),
        ("answer_keys.json", keys, dict),
        ("resources.json", resources, list),
    ):
        if not isinstance(value, expected):
            report.error(f"{name}: top level must be a {expected.__name__}")
    if not report.ok:
        return report

    _check_bilingual(course.get("name"), "course.name", report, require_arabic=True)
    if "owner_id" not in course:
        report.error("course.json: missing owner_id (use null in seed files)")
    elif course["owner_id"] is not None and not (isinstance(course["owner_id"], str) and course["owner_id"]):
        report.error("course.json: owner_id must be a non-empty string or null")

    # Materials (optional)
    material_ids: set[str] = set()
    if (course_dir / OPTIONAL_MATERIALS_FILE).exists():
        materials = _load(course_dir / OPTIONAL_MATERIALS_FILE, report)
        if materials is not None:
            if not isinstance(materials, list):
                report.error(f"{OPTIONAL_MATERIALS_FILE}: top level must be a list")
            else:
                material_ids = _unique_ids(materials, "materials", report)
                for m in materials:
                    if isinstance(m, dict) and "id" in m and m.get("status") not in ALLOWED_MATERIAL_STATUS:
                        report.error(f"material '{m['id']}': status '{m.get('status')}' not in {sorted(ALLOWED_MATERIAL_STATUS)}")

    # Concepts
    concept_ids = _unique_ids(concepts, "concepts", report)
    not_approved = 0
    graph: dict[str, list[str]] = {}
    for c in concepts:
        if not isinstance(c, dict) or "id" not in c:
            continue
        where = f"concept '{c['id']}'"
        _check_bilingual(c.get("name"), f"{where}.name", report, require_arabic=True)
        if "description" in c:
            _check_bilingual(c.get("description"), f"{where}.description", report, require_arabic=True)
        prereqs = c.get("prerequisites", [])
        if not isinstance(prereqs, list):
            report.error(f"{where}: prerequisites must be a list")
            prereqs = []
        for p in prereqs:
            if p == c["id"]:
                report.error(f"{where}: lists itself as a prerequisite")
            elif p not in concept_ids:
                report.error(f"{where}: unknown prerequisite '{p}'")
        graph[c["id"]] = [p for p in prereqs if p in concept_ids and p != c["id"]]
        if not _check_provenance(c, where, report, material_ids):
            not_approved += 1
    cycle = _find_cycle(graph)
    if cycle:
        report.error("concepts: prerequisite cycle " + " -> ".join(cycle))

    # Questions
    question_ids = _unique_ids(questions, "questions", report)
    option_ids_by_question: dict[str, set[str]] = {}
    questions_per_concept = {cid: 0 for cid in concept_ids}
    for q in questions:
        if not isinstance(q, dict) or "id" not in q:
            continue
        where = f"question '{q['id']}'"
        leaked = FORBIDDEN_QUESTION_FIELDS & set(q)
        if leaked:
            report.error(f"{where}: contains answer field(s) {sorted(leaked)}; keep answers in answer_keys.json")
        _check_bilingual(q.get("prompt"), f"{where}.prompt", report, require_arabic=True)
        cids = q.get("concept_ids")
        if not isinstance(cids, list) or not cids:
            report.error(f"{where}: concept_ids must be a non-empty list")
            cids = []
        for cid in cids:
            if cid not in concept_ids:
                report.error(f"{where}: unknown concept '{cid}'")
            else:
                questions_per_concept[cid] += 1
        options = q.get("options")
        if not isinstance(options, list) or len(options) < 2:
            report.error(f"{where}: needs at least 2 options")
            options = []
        opt_ids: set[str] = set()
        for i, opt in enumerate(options):
            oid = opt.get("id") if isinstance(opt, dict) else None
            if not isinstance(oid, str) or not oid:
                report.error(f"{where}.options[{i}]: missing 'id'")
                continue
            if oid in opt_ids:
                report.error(f"{where}: duplicate option id '{oid}'")
            opt_ids.add(oid)
            if FORBIDDEN_QUESTION_FIELDS & set(opt):
                report.error(f"{where}.options['{oid}']: contains an answer field")
            _check_bilingual(opt.get("text"), f"{where}.options['{oid}'].text", report)
        option_ids_by_question[q["id"]] = opt_ids
        version = q.get("version")
        if isinstance(version, bool) or not isinstance(version, int) or version < 1:
            report.error(f"{where}: version must be an integer >= 1")
        if not _check_provenance(q, where, report, material_ids):
            not_approved += 1

    # Answer keys
    for qid in question_ids:
        key = keys.get(qid)
        if key is None:
            report.error(f"answer_keys: no key for question '{qid}'")
            continue
        correct = key.get("correct_option_id") if isinstance(key, dict) else None
        if correct not in option_ids_by_question.get(qid, set()):
            report.error(f"answer_keys['{qid}']: correct_option_id '{correct}' is not one of the question's options")
    for qid in keys:
        if qid not in question_ids:
            report.error(f"answer_keys: key for unknown question '{qid}'")

    # Resources
    _unique_ids(resources, "resources", report)
    for r in resources:
        if not isinstance(r, dict) or "id" not in r:
            continue
        where = f"resource '{r['id']}'"
        _check_bilingual(r.get("title"), f"{where}.title", report, require_arabic=True)
        cids = r.get("concept_ids")
        if not isinstance(cids, list) or not cids:
            report.error(f"{where}: concept_ids must be a non-empty list")
        else:
            for cid in cids:
                if cid not in concept_ids:
                    report.error(f"{where}: unknown concept '{cid}'")
        rtype = r.get("type")
        if rtype not in RESOURCE_TYPES:
            report.error(f"{where}: type '{rtype}' not in {sorted(RESOURCE_TYPES)}")
        elif rtype in ("link", "video"):
            url = r.get("url")
            if not (isinstance(url, str) and url.startswith(("https://", "http://"))):
                report.error(f"{where}: type '{rtype}' needs an http(s) url")
        elif rtype == "file":
            path = r.get("storage_path")
            if not (isinstance(path, str) and path):
                report.error(f"{where}: type 'file' needs a storage_path")
        elif rtype == "activity":
            _check_bilingual(r.get("description"), f"{where}.description", report, require_arabic=True)
        if r.get("language") not in RESOURCE_LANGUAGES:
            report.error(f"{where}: language '{r.get('language')}' not in {sorted(RESOURCE_LANGUAGES)}")
        if not _check_provenance(r, where, report, material_ids):
            not_approved += 1

    # Warnings
    for cid, count in sorted(questions_per_concept.items()):
        if count < MIN_QUESTIONS_PER_CONCEPT:
            report.warn(f"concept '{cid}' has {count} question(s); fewer than {MIN_QUESTIONS_PER_CONCEPT} cannot move past 'insufficient evidence'")
    if not_approved:
        report.warn(f"{not_approved} item(s) are not yet approved by human review")

    return report


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print(__doc__.strip().splitlines()[2], file=sys.stderr)
        return 2
    report = validate_course(Path(argv[1]))
    for w in report.warnings:
        print(f"WARNING: {w}")
    for e in report.errors:
        print(f"ERROR: {e}")
    print(f"{len(report.errors)} error(s), {len(report.warnings)} warning(s)")
    return 0 if report.ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
