# مهمة: لوحة المدرّس المباشرة (Live Insights)

**لمين:** مسؤولة تطبيق المدرّس (`src/app/lib/features/instructor/`).
**المرحلة:** 4 بـ `docs/implementation-plan.md`.
**نوع المهمة:** ميزة جديدة (new feature).
**الموعد:** قبل يوم الجمعة 27/11، لنلحق نجرّب كل شي قبل المسابقة يوم السبت 28/11.
**للأسئلة:** ميسم (Backend). أي تعديل خارج مجلدك، خبّري صاحبته أول.

---

## 1. الفكرة بجملتين

هلّق المدرّس بيشوف بس "طلاب أجابوا: N · مجموع الإجابات: M". بدنا تحت هالسطر، خلال الجلسة، يشوف **أي مفهوم الصف ضعيف فيه، وليش ممكن**، مع الدليل (كم طالب، وكم بالمية صح). هاد اللي بيبيّن للحكّام قيمة بوصلة التعليمية، وهي أكبر نسبة بالتقييم (30%).

---

## 2. تجهيز جهازك (مرة وحدة)

### البرامج
| البرنامج | النسخة | ليش |
|---|---|---|
| Git | أي نسخة | |
| Flutter | **3.38.x stable** (نفس نسخة الفريق) | التطبيق |
| Node.js | 20 أو أحدث | أدوات Firebase والسكربتات |
| Java (JDK) | 17 أو أحدث | محاكي Firebase المحلي |
| Chrome | | تشغيل التطبيق |
| VS Code + إضافة Flutter | | اختياري، بس أسهل |

تأكدي:
```bash
flutter --version
```
```bash
node --version
```
```bash
java -version
```

### جيبي الكود وافتحي فرعك
```bash
git clone https://github.com/MaysamMB/Bousla.git
```
```bash
cd Bousla
```
```bash
git fetch origin maysam-work
```
```bash
git checkout -b feature/live-insights origin/maysam-work
```

### جهّزي المشروع
```bash
cd src/engine
```
```bash
dart pub get
```
```bash
cd ../app
```
```bash
flutter pub get
```
```bash
flutter gen-l10n
```
```bash
cd ../..
```

### تأكدي إنه كل شي سليم قبل ما تغيّري إشي
من جذر المشروع:
```bash
.\bousla test
```
لازم يطلع `flutter analyze` بدون مشاكل، و`All tests passed` (79 اختبار)، و27 اختبار قواعد.
على Mac/Linux استعملي `./scripts/bousla.sh` بدل `.\bousla`.

---

## 3. كيف تشغّلي التطبيق وإنتِ عم تشتغلي

في 3 طرق. **للتطوير استعملي الطريقة ب**، ولا تجرّبي على المشروع الحقيقي، عشان ما نخرب بيانات العرض.

### أ. بدون Firebase (أسرع، للشكل بس)
```bash
.\bousla demo
```
البيانات بالذاكرة، وبتنمسح مع كل تشغيل. المدرّس والطالب لازم يكونوا بنفس التبويب: اعملي جلسة، ارجعي للرئيسية، وانضمي بالكود.
⚠️ هون في 3 أسئلة بس وطالب واحد، فكل المفاهيم رح تكون **مخفية** (شوفي قسم 5). منيحة للتصميم بس.

### ب. Firebase على جهازك (المحاكي) ← **هاي الطريقة الأساسية**
**Terminal 1** (خليه مفتوح):
```bash
.\bousla emulators
```
**Terminal 2:** حمّلي المقرر على المحاكي، مرة بكل تشغيل للمحاكي:
```bash
cd firebase
```
```bash
$env:BOUSLA_EMAIL="teacher@test.dev"; $env:BOUSLA_PASSWORD="secret123"; node tools/seed.mjs --env ../src/app/firebase.env.emulator.json --approve-concepts --create-account
```
```bash
cd ..
```
**Terminal 2:** شغّلي التطبيق:
```bash
.\bousla emulator-run
```
1. ادخلي كمدرّس: `teacher@test.dev` / `secret123` (موجود بالمحاكي بس).
2. **مراجعة الأسئلة** ← اعتمدي 5-6 أسئلة من مفاهيم مختلفة. نصيحة: اختاري مفهوم ومتطلّبه السابق، مثلاً `db_pk_*` (المفتاح الأساسي) و`db_fk_*` (المفتاح الخارجي، ومتطلّبه المفتاح الأساسي)، عشان تشوفي إشارات المتطلبات السابقة.
3. **إنشاء جلسة** ← انسخي الكود.

**Terminal 3:** طلاب وهميين بيجاوبوا (6 طلاب، نصهم عربي ونصهم إنجليزي، إجابات عشوائية):
```bash
.\bousla simulate ABC234
```
(حطي الكود الحقيقي مكان `ABC234`. وإذا بدك عدد تاني: `.\bousla simulate ABC234 --students 10`)

رح يتحدّث العدّاد عند المدرّس لحاله. شغّلي الأمر كمان مرة لتزيدي طلاب. الإجابات عشوائية، فالنتيجة ما إلها معنى تعليمي، بس كافية لتشوفي اللوحة.
وإذا بدك تجاوبي بنفسك كطالب: افتحي نافذة خفية على الرابط اللي بيطلع تحت الكود.

### ج. المشروع الحقيقي (للتجربة النهائية بس)
```bash
.\bousla run
```
بيحتاج ملف `src/app/firebase.env.json` (مش موجود على GitHub). خدي القيم من ميسم بشكل خاص، أو انسخيها بنفسك من Firebase console ← Project settings ← Your apps ← Config. **انسخي `apiKey` من الكونسول مباشرة**، مش من الشات: بعض الواجهات بتخبّي المفتاح بـ `•••`. `.\bousla check` بيكشف هالمشكلة.

---

## 4. شو بالضبط المطلوب

### البيانات موجودة كلها، والمحرّك جاهز ومجرّب (54 اختبار)

| بدك | من وين |
|---|---|
| إجابات الجلسة (مباشرة) | `services.sessions.watchResponses(session.id)` |
| الأسئلة بنفس نسخ الجلسة | `services.content.questionsForSession(session.courseId, session.questions)` ← خدي `q.question` |
| مفاتيح الإجابات (للمدرّس بس) | `services.content.answerKeys(session.courseId)` |
| المفاهيم وأسماؤها بالعربي والإنجليزي | `services.content.listConcepts(session.courseId)` |

### الحساب، بالترتيب (كله من `package:bousla_engine/bousla_engine.dart`)
```dart
final result = scoreResponses(responses: responses, questions: questions, keys: keys);
final evidence = evidenceByParticipant(
  scored: result.scored,
  conceptIds: [for (final c in concepts) c.id],
);
final masteries = {
  for (final e in evidence.entries) e.key: estimateAll(e.value),
};
final insights = buildClassInsights(
  masteriesByParticipant: masteries,
  concepts: concepts,
  minGroupSize: 5,
);
```
النتيجة `ClassInsights`:
- `participantCount`
- `concepts`: لكل مفهوم `ConceptClassSummary`، وفيه:
  - `conceptId`
  - `respondents`
  - `suppressed`
  - `stateCounts` (كم طالب بكل حالة: `insufficientEvidence` / `possibleDifficulty` / `emerging` / `demonstratedMastery`)
  - `pooledAccuracy` (نسبة الصح، وبتكون `null` إذا المفهوم مخفي)
- `prerequisiteSignals`: لكل إشارة `conceptId`، و`prerequisiteId`، و`participantsWithPossibleGap`، و`participantsStrugglingWithConcept`.

اقري التعليقات بـ `src/engine/lib/src/class_insights.dart` و`mastery_estimator.dart` قبل ما تبلّشي.

### وين تحطي الكود
```
src/app/lib/features/instructor/live_insights/
  live_insights.dart          ← دالة بتحسب ClassInsights من البيانات (بدون Flutter، عشان تنفحص بسهولة)
  live_insights_panel.dart    ← الواجهة
```
وحطي `LiveInsightsPanel` تحت سطر العدّاد بـ `_LiveSessionPanel` بملف `sessions/create_session_screen.dart`.

نصيحة: الأسئلة والمفاتيح والمفاهيم حمّليها **مرة وحدة** لما تفتح الجلسة. والإجابات بس هي اللي بتتحدّث مع `StreamBuilder`، وبكل تحديث أعيدي الحساب، لأنه سريع.

### شو لازم يطلع على الشاشة
1. **لكل مفهوم:** اسمه بلغة الواجهة، و"X طالب أجابوا"، ونسبة الصح، وتوزيع الحالات (مثلاً شريط ملوّن، أو أرقام بسيطة).
2. **ترتيب:** المفاهيم اللي فيها صعوبة أول.
3. **المفهوم المخفي** (`suppressed`): بدون أرقام نهائياً. بس "أقل من 5 طلاب، مخفي لحماية الخصوصية".
4. **إشارات المتطلبات السابقة:** جملة متل:
   > "قد يكون **المفتاح الأساسي** سبباً محتملاً لصعوبة **المفتاح الخارجي** (3 طلاب)"
5. **قبل أي إجابة:** رسالة "بانتظار إجابات الطلاب".
6. **عربي وإنجليزي:** كل النصوص بملفي `app_ar.arb` و`app_en.arb`، وأسماء المفاتيح بتبلّش بـ `instructor…`. والاتجاه بيتبع اللغة لحاله (ما تكتبي RTL/LTR يدوي).

### ممنوع (قواعد المشروع، والحكّام بيدقّقوا عليها)
- ❌ **أسماء طلاب أو UID أو إجابات فردية بالشاشة.** اللوحة **مجمّعة بس**.
- ❌ **أرقام لمفهوم مخفي.**
- ❌ **كلام قاطع** متل "الطلاب عندهم فجوة" أو "السبب هو…". استعملي "قد"، "محتمل"، "يحتاج مراجعة"، "بحاجة لأدلة أكثر".
- ❌ **تغيير `minGroupSize` لأقل من 5 بالنسخة النهائية.** للتطوير استعملي `.\bousla simulate` بدل ما تنزّليه.
- ❌ **تعديل المحرّك** (`src/engine`) **أو القواعد** (`firebase/`). إذا احتجتي شي منهم، احكي مع ميسم.

---

## 5. ليش في مفاهيم "مخفية"؟
إذا جاوب على مفهوم أقل من 5 طلاب، الأرقام ممكن تكشف مين ضعيف (مثلاً إذا طالبين بس جاوبوا، وواحد منهم غلط). فالمحرّك بيخفيهم لحاله. هاي ميزة خصوصية بنحكي عنها بالعرض، مش خطأ.

---

## 6. الاختبارات (مطلوبة قبل الدمج)
بـ `src/app/test/`:

1. **`live_insights_test.dart`** (منطق بدون واجهة):
   - 6 طلاب: مفهوم معظمهم غلطوا فيه بيطلع `possibleDifficulty` وبيكون أول بالترتيب.
   - 4 طلاب بس: المفهوم `suppressed`، و`pooledAccuracy == null`.
   - ولا إجابة: كل المفاهيم مخفية، و`participantCount == 0`.
   - نفس الخيارات بالعربي وبالإنجليزي بتعطي **نفس النتيجة**.
2. **widget test للوحة:**
   - المفهوم المخفي ما بيطلع فيه ولا رقم.
   - نص إشارة المتطلب السابق فيه "قد يكون" بالعربي (و"may" بالإنجليزي).
   - ما في أي UID ظاهر على الشاشة.

ملاحظة من تجربتنا: بالـ widget tests لا تستعملي `pumpAndSettle()` وفي حقل نص عليه focus (المؤشر اللي بيرمش ما بيخلّيه يخلص). وإذا رسمتي نفس الشاشة مرتين بالاختبار، أعطيها `key` مختلف.

شغّليهم:
```bash
.\bousla test
```

---

## 7. لما تخلصي
1. `.\bousla test` كله أخضر.
2. جرّبي يدوياً على المحاكي:
   - جلسة، و`.\bousla simulate` بـ 6 طلاب ← لازم تطلع أرقام.
   - جلسة تانية، و`.\bousla simulate` بـ 3 طلاب ← لازم يطلع كله مخفي.
   - بدّلي اللغة خلال الجلسة.
3. Commit وPush على فرعك `feature/live-insights`، وافتحي Pull Request على `maysam-work`.
4. حدّثي سطر الحالة بالمرحلة 4 بـ `docs/implementation-plan.md`. اكتبي بالضبط شو شغّلتي ووين (متل "flutter test 85/85 على جهاز X").
5. خبّري ميسم لننشر ونجرّب من موبايلات حقيقية.

## 8. إذا علقتي
| المشكلة | الحل |
|---|---|
| `isn't defined for the type 'AppLocalizations'` | `flutter gen-l10n` بـ `src/app` |
| `.\bousla` مش معروف | لازم تكوني بجذر المشروع (`Bousla`)، مش بـ `src/app` |
| المحاكي ما بيشتغل | تأكدي من Java (`java -version`)، وإنه ما في محاكي تاني شغّال |
| التطبيق على المحاكي بيعطي خطأ دخول | المحاكي بينمسح لما يتسكّر، فأعيدي أمر `seed` |
| الموقع المنشور بيعرض نسخة قديمة | نافذة خفية، أو F12 ← Application ← Clear site data |
