// Small bilingual sample used by the in-memory repositories during
// development. Taken from data/courses/database-systems. Most items are marked
// approved here only so screens have something to show; the db_rm_* questions
// keep their real status (AI draft, pending review) for the review screen.
// Not used in production.

const sampleCourse = {
  'id': 'database_systems',
  'name': {'ar': 'أنظمة قواعد البيانات', 'en': 'Database Systems'},
};

const _approved = {'source': 'team', 'status': 'approved'};
const _aiDraft = {'source': 'ai_draft', 'status': 'pending_review'};

const sampleConcepts = [
  {
    'id': 'relational_model',
    'name': {'ar': 'النموذج العلائقي', 'en': 'Relational Model'},
    'prerequisites': <String>[],
    'provenance': _approved,
  },
  {
    'id': 'primary_key',
    'name': {'ar': 'المفتاح الأساسي', 'en': 'Primary Key'},
    'prerequisites': ['relational_model'],
    'provenance': _approved,
  },
  {
    'id': 'foreign_key',
    'name': {'ar': 'المفتاح الخارجي', 'en': 'Foreign Key'},
    'prerequisites': ['primary_key'],
    'provenance': _approved,
  },
];

const sampleQuestions = [
  {
    'id': 'db_pk_001',
    'version': 1,
    'concept_ids': ['primary_key'],
    'prompt': {
      'ar': 'أيّ خاصية يجب أن يحققها المفتاح الأساسي (Primary Key)؟',
      'en': 'Which property must a primary key have?',
    },
    'options': [
      {
        'id': 'a',
        'text': {
          'ar': 'أن يكون فريداً ولا يقبل القيمة الفارغة (NULL)',
          'en': 'Unique and not NULL',
        },
      },
      {
        'id': 'b',
        'text': {
          'ar': 'أن يسمح بالقيم المكررة',
          'en': 'It may contain duplicate values',
        },
      },
      {
        'id': 'c',
        'text': {
          'ar': 'أن يكون من نوع نصّي دائماً',
          'en': 'It must always be a text column',
        },
      },
    ],
    'provenance': _approved,
  },
  {
    'id': 'db_pk_002',
    'version': 1,
    'concept_ids': ['primary_key'],
    'prompt': {
      'ar': 'في الجدول Student(student_id, name, gpa)، ما أنسب مفتاح أساسي؟',
      'en': 'In the table Student(student_id, name, gpa), which is the most suitable primary key?',
    },
    'options': [
      {
        'id': 'a',
        'text': {'ar': 'name', 'en': 'name'},
      },
      {
        'id': 'b',
        'text': {'ar': 'student_id', 'en': 'student_id'},
      },
      {
        'id': 'c',
        'text': {'ar': 'gpa', 'en': 'gpa'},
      },
    ],
    'provenance': _approved,
  },
  {
    'id': 'db_fk_001',
    'version': 1,
    'concept_ids': ['foreign_key'],
    'prompt': {
      'ar': 'ما وظيفة المفتاح الخارجي (Foreign Key)؟',
      'en': 'What is the purpose of a foreign key?',
    },
    'options': [
      {
        'id': 'a',
        'text': {'ar': 'تشفير البيانات', 'en': 'Encrypt the data'},
      },
      {
        'id': 'b',
        'text': {
          'ar': 'تسريع ترتيب النتائج',
          'en': 'Speed up sorting of results',
        },
      },
      {
        'id': 'c',
        'text': {
          'ar': 'ربط صف بصف في جدول آخر عبر مفتاحه الأساسي',
          'en': 'Link a row to a row in another table through its primary key',
        },
      },
    ],
    'provenance': _approved,
  },
  {
    'id': 'db_fk_002',
    'version': 1,
    'concept_ids': ['foreign_key'],
    'prompt': {
      'ar': 'ماذا يحدث عند إدخال تسجيل بقيمة student_id غير موجودة في الجدول Student مع تفعيل قيد المفتاح الخارجي؟',
      'en': 'With the foreign key enforced, what happens when inserting an enrollment whose student_id is not in Student?',
    },
    'options': [
      {
        'id': 'a',
        'text': {
          'ar': 'يُرفض الإدخال للحفاظ على سلامة المراجع',
          'en': 'The insert is rejected',
        },
      },
      {
        'id': 'b',
        'text': {
          'ar': 'يُنشأ الطالب تلقائياً',
          'en': 'The student is created automatically',
        },
      },
    ],
    'provenance': _approved,
  },
  {
    'id': 'db_rm_001',
    'version': 1,
    'concept_ids': ['relational_model'],
    'prompt': {
      'ar': 'في النموذج العلائقي، ماذا يُسمّى الجدول؟',
      'en': 'In the relational model, what is a table called?',
    },
    'options': [
      {
        'id': 'a',
        'text': {'ar': 'سمة (Attribute)', 'en': 'An attribute'},
      },
      {
        'id': 'b',
        'text': {'ar': 'مجال (Domain)', 'en': 'A domain'},
      },
      {
        'id': 'c',
        'text': {'ar': 'صف (Tuple)', 'en': 'A tuple'},
      },
      {
        'id': 'd',
        'text': {'ar': 'علاقة (Relation)', 'en': 'A relation'},
      },
    ],
    'provenance': _aiDraft,
  },
  {
    'id': 'db_rm_002',
    'version': 1,
    'concept_ids': ['relational_model'],
    'prompt': {
      'ar': 'ماذا يمثّل كل صف (Tuple) في العلاقة؟',
      'en': 'What does each row (tuple) in a relation represent?',
    },
    'options': [
      {
        'id': 'a',
        'text': {'ar': 'سجلاً واحداً لكيان معيّن', 'en': 'A single record of one entity'},
      },
      {
        'id': 'b',
        'text': {'ar': 'قيداً على الجدول', 'en': 'A constraint on the table'},
      },
      {
        'id': 'c',
        'text': {'ar': 'قاعدة البيانات كاملة', 'en': 'The whole database'},
      },
      {
        'id': 'd',
        'text': {'ar': 'نوع بيانات العمود', 'en': 'The data type of a column'},
      },
    ],
    'provenance': _aiDraft,
  },
];

const sampleAnswerKeys = {
  'db_pk_001': {'correct_option_id': 'a'},
  'db_pk_002': {'correct_option_id': 'b'},
  'db_fk_001': {'correct_option_id': 'c'},
  'db_fk_002': {'correct_option_id': 'a'},
  'db_rm_001': {'correct_option_id': 'd'},
  'db_rm_002': {'correct_option_id': 'a'},
};

const sampleResources = [
  {
    'id': 'res_primary_key_practice',
    'concept_ids': ['primary_key'],
    'type': 'activity',
    'language': 'both',
    'title': {'ar': 'تدريب: المفتاح الأساسي', 'en': 'Practice: Primary Key'},
    'url': null,
    'provenance': _approved,
  },
];
