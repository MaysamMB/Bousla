"""Tests for validate_data.py.

Run from the repository root:
    python -m unittest discover -s src/ai/tests -v
"""
import copy
import json
import sys
import tempfile
import unittest
from pathlib import Path

AI_DIR = Path(__file__).resolve().parents[1]
REPO_ROOT = AI_DIR.parents[1]
sys.path.insert(0, str(AI_DIR))

import validate_data  # noqa: E402

PROV = {"source": "team", "status": "approved", "reviewed_by": "test", "source_material_id": None, "source_location": None}


def t(ar, en):
    return {"ar": ar, "en": en}


def minimal_dataset():
    return {
        "course.json": {"id": "c", "name": t("مقرر", "Course"), "owner_id": None},
        "concepts.json": [
            {"id": "pk", "name": t("المفتاح الأساسي", "Primary Key"), "prerequisites": [], "provenance": dict(PROV)},
            {"id": "fk", "name": t("المفتاح الخارجي", "Foreign Key"), "prerequisites": ["pk"], "provenance": dict(PROV)},
        ],
        "questions.json": [
            {
                "id": f"q{i}",
                "version": 1,
                "concept_ids": [cid],
                "prompt": t("سؤال؟", "Question?"),
                "options": [
                    {"id": "a", "text": t("أ", "A")},
                    {"id": "b", "text": t("ب", "B")},
                ],
                "provenance": dict(PROV),
            }
            for i, cid in enumerate(["pk", "pk", "fk", "fk"])
        ],
        "answer_keys.json": {f"q{i}": {"correct_option_id": "a"} for i in range(4)},
        "resources.json": [
            {
                "id": "r1",
                "concept_ids": ["fk"],
                "type": "activity",
                "language": "both",
                "title": t("تدريب", "Practice"),
                "description": t("نشاط تدريبي", "A practice activity"),
                "provenance": dict(PROV),
            },
        ],
    }


class ValidateDataTests(unittest.TestCase):
    def run_on(self, dataset):
        with tempfile.TemporaryDirectory() as tmp:
            for name, content in dataset.items():
                Path(tmp, name).write_text(json.dumps(content, ensure_ascii=False), encoding="utf-8")
            return validate_data.validate_course(Path(tmp))

    def assertErrorContains(self, report, fragment):
        self.assertFalse(report.ok, "expected errors but validation passed")
        self.assertTrue(any(fragment in e for e in report.errors), f"no error containing {fragment!r}: {report.errors}")

    def test_minimal_valid_dataset_passes(self):
        report = self.run_on(minimal_dataset())
        self.assertTrue(report.ok, report.errors)
        self.assertEqual(report.warnings, [])

    def test_real_database_systems_dataset_has_no_errors(self):
        report = validate_data.validate_course(REPO_ROOT / "data" / "courses" / "database-systems")
        self.assertTrue(report.ok, report.errors)

    def test_missing_file(self):
        ds = minimal_dataset()
        del ds["answer_keys.json"]
        self.assertErrorContains(self.run_on(ds), "answer_keys.json: file is missing")

    def test_duplicate_question_id(self):
        ds = minimal_dataset()
        ds["questions.json"][1]["id"] = "q0"
        self.assertErrorContains(self.run_on(ds), "duplicate id 'q0'")

    def test_missing_english_translation(self):
        ds = minimal_dataset()
        ds["questions.json"][0]["prompt"] = {"ar": "سؤال؟"}
        self.assertErrorContains(self.run_on(ds), "missing or empty 'en'")

    def test_empty_arabic_option(self):
        ds = minimal_dataset()
        ds["questions.json"][0]["options"][1]["text"]["ar"] = "  "
        self.assertErrorContains(self.run_on(ds), "missing or empty 'ar'")

    def test_arabic_field_without_arabic_letters(self):
        ds = minimal_dataset()
        ds["questions.json"][0]["prompt"]["ar"] = "Question copied in English"
        self.assertErrorContains(self.run_on(ds), "contains no Arabic letters")

    def test_code_only_options_are_allowed_in_both_languages(self):
        ds = minimal_dataset()
        ds["questions.json"][0]["options"][0]["text"] = t("SELECT * FROM T;", "SELECT * FROM T;")
        self.assertTrue(self.run_on(ds).ok)

    def test_unknown_concept_reference(self):
        ds = minimal_dataset()
        ds["questions.json"][0]["concept_ids"] = ["nope"]
        self.assertErrorContains(self.run_on(ds), "unknown concept 'nope'")

    def test_unknown_prerequisite(self):
        ds = minimal_dataset()
        ds["concepts.json"][1]["prerequisites"] = ["nope"]
        self.assertErrorContains(self.run_on(ds), "unknown prerequisite 'nope'")

    def test_self_prerequisite(self):
        ds = minimal_dataset()
        ds["concepts.json"][0]["prerequisites"] = ["pk"]
        self.assertErrorContains(self.run_on(ds), "lists itself")

    def test_prerequisite_cycle(self):
        ds = minimal_dataset()
        ds["concepts.json"][0]["prerequisites"] = ["fk"]
        self.assertErrorContains(self.run_on(ds), "prerequisite cycle")

    def test_answer_embedded_in_question_is_rejected(self):
        ds = minimal_dataset()
        ds["questions.json"][0]["correct_option_id"] = "a"
        self.assertErrorContains(self.run_on(ds), "keep answers in answer_keys.json")

    def test_question_without_key(self):
        ds = minimal_dataset()
        del ds["answer_keys.json"]["q2"]
        self.assertErrorContains(self.run_on(ds), "no key for question 'q2'")

    def test_key_not_matching_any_option(self):
        ds = minimal_dataset()
        ds["answer_keys.json"]["q0"] = {"correct_option_id": "z"}
        self.assertErrorContains(self.run_on(ds), "is not one of the question's options")

    def test_key_for_unknown_question(self):
        ds = minimal_dataset()
        ds["answer_keys.json"]["ghost"] = {"correct_option_id": "a"}
        self.assertErrorContains(self.run_on(ds), "unknown question 'ghost'")

    def test_duplicate_option_id(self):
        ds = minimal_dataset()
        ds["questions.json"][0]["options"][1]["id"] = "a"
        self.assertErrorContains(self.run_on(ds), "duplicate option id 'a'")

    def test_single_option_question(self):
        ds = minimal_dataset()
        ds["questions.json"][0]["options"] = ds["questions.json"][0]["options"][:1]
        self.assertErrorContains(self.run_on(ds), "at least 2 options")

    def test_invalid_provenance_status(self):
        ds = minimal_dataset()
        ds["concepts.json"][0]["provenance"]["status"] = "done"
        self.assertErrorContains(self.run_on(ds), "provenance.status")

    def test_resource_unknown_concept(self):
        ds = minimal_dataset()
        ds["resources.json"][0]["concept_ids"] = ["nope"]
        self.assertErrorContains(self.run_on(ds), "resource 'r1': unknown concept 'nope'")

    def test_invalid_json(self):
        with tempfile.TemporaryDirectory() as tmp:
            for name, content in minimal_dataset().items():
                Path(tmp, name).write_text(json.dumps(content), encoding="utf-8")
            Path(tmp, "questions.json").write_text("{not json", encoding="utf-8")
            report = validate_data.validate_course(Path(tmp))
        self.assertErrorContains(report, "questions.json: invalid JSON")

    def test_warns_when_concept_has_too_few_questions(self):
        ds = minimal_dataset()
        ds["questions.json"] = ds["questions.json"][:3]
        del ds["answer_keys.json"]["q3"]
        report = self.run_on(ds)
        self.assertTrue(report.ok, report.errors)
        self.assertTrue(any("concept 'fk' has 1 question" in w for w in report.warnings), report.warnings)

    def test_warns_about_unreviewed_items(self):
        ds = minimal_dataset()
        ds["questions.json"][0]["provenance"]["status"] = "pending_review"
        report = self.run_on(ds)
        self.assertTrue(report.ok, report.errors)
        self.assertTrue(any("not yet approved" in w for w in report.warnings), report.warnings)

    # Instructor-owned content, versions and provenance

    def test_course_without_owner_field(self):
        ds = minimal_dataset()
        del ds["course.json"]["owner_id"]
        self.assertErrorContains(self.run_on(ds), "missing owner_id")

    def test_course_with_owner_uid_passes(self):
        ds = minimal_dataset()
        ds["course.json"]["owner_id"] = "instructorUid123"
        self.assertTrue(self.run_on(ds).ok)

    def test_question_without_version(self):
        ds = minimal_dataset()
        del ds["questions.json"][0]["version"]
        self.assertErrorContains(self.run_on(ds), "version must be an integer >= 1")

    def test_question_version_zero(self):
        ds = minimal_dataset()
        ds["questions.json"][0]["version"] = 0
        self.assertErrorContains(self.run_on(ds), "version must be an integer >= 1")

    def test_invalid_provenance_source(self):
        ds = minimal_dataset()
        ds["questions.json"][0]["provenance"]["source"] = "internet"
        self.assertErrorContains(self.run_on(ds), "provenance.source")

    def test_source_material_must_exist(self):
        ds = minimal_dataset()
        ds["questions.json"][0]["provenance"]["source_material_id"] = "mat_1"
        self.assertErrorContains(self.run_on(ds), "unknown source_material_id 'mat_1'")

    def test_source_material_listed_in_materials_passes(self):
        ds = minimal_dataset()
        ds["questions.json"][0]["provenance"].update(source="ai_draft", source_material_id="mat_1", source_location="p. 3")
        ds["materials.json"] = [{"id": "mat_1", "title": "Lecture 1", "status": "ready_for_review"}]
        self.assertTrue(self.run_on(ds).ok)

    def test_invalid_material_status(self):
        ds = minimal_dataset()
        ds["materials.json"] = [{"id": "mat_1", "status": "done"}]
        self.assertErrorContains(self.run_on(ds), "material 'mat_1': status")

    def test_resource_invalid_type(self):
        ds = minimal_dataset()
        ds["resources.json"][0]["type"] = "podcast"
        self.assertErrorContains(self.run_on(ds), "type 'podcast'")

    def test_video_resource_needs_url(self):
        ds = minimal_dataset()
        ds["resources.json"][0].update(type="video", url=None)
        self.assertErrorContains(self.run_on(ds), "needs an http(s) url")

    def test_link_resource_with_url_passes(self):
        ds = minimal_dataset()
        ds["resources.json"][0].update(type="link", url="https://example.org/fk", added_by="instructorUid123")
        ds["resources.json"][0]["provenance"]["source"] = "instructor"
        self.assertTrue(self.run_on(ds).ok)

    def test_file_resource_needs_storage_path(self):
        ds = minimal_dataset()
        ds["resources.json"][0].update(type="file", storage_path=None)
        self.assertErrorContains(self.run_on(ds), "needs a storage_path")

    def test_resource_invalid_language(self):
        ds = minimal_dataset()
        ds["resources.json"][0]["language"] = "fr"
        self.assertErrorContains(self.run_on(ds), "language 'fr'")

    def test_does_not_mutate_input(self):
        ds = minimal_dataset()
        before = copy.deepcopy(ds)
        self.run_on(ds)
        self.assertEqual(ds, before)


if __name__ == "__main__":
    unittest.main()
