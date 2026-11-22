import 'package:bousla_engine/bousla_engine.dart';
import 'package:flutter/material.dart';

import '../../../app_services.dart';
import '../../../data/models.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/language.dart';
import '../../../shared/widgets/language_switcher.dart';

/// One question at a time, in the student's chosen language (owner: student
/// web portal). Switching language mid-way keeps the same question and
/// options; only the text and direction change, and each answer records the
/// language it was shown in. To do: feedback screen after release, progress
/// saving on reload, accessibility review.
class AnsweringScreen extends StatefulWidget {
  const AnsweringScreen({
    super.key,
    required this.session,
    required this.participantId,
  });

  final Session session;
  final String participantId;

  @override
  State<AnsweringScreen> createState() => _AnsweringScreenState();
}

class _AnsweringScreenState extends State<AnsweringScreen> {
  Future<List<QuestionView>>? _questions;
  var _index = 0;
  String? _selected;
  String? _error;
  var _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _questions ??= _load();
  }

  /// Approved questions of this session, in the session's order.
  Future<List<QuestionView>> _load() async {
    final all = await ServicesScope.of(context).content
        .listQuestions(widget.session.courseId);
    final byRef = {for (final q in all) QuestionRef(q.id, q.version): q};
    return [
      for (final ref in widget.session.questions)
        if (byRef[ref] != null) byRef[ref]!,
    ];
  }

  Future<void> _submit(QuestionView q) async {
    final l = AppLocalizations.of(context);
    final language = currentLanguage(context);
    final sessions = ServicesScope.of(context).sessions;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await sessions.submitResponse(
        widget.session.id,
        Response(
          participantId: widget.participantId,
          questionId: q.id,
          questionVersion: q.version,
          selectedOptionId: _selected!,
          displayLanguage: language,
        ),
      );
      _next();
    } on DuplicateAnswerException {
      _next();
    } on SessionClosedException {
      if (mounted) setState(() => _error = l.studentSessionClosed);
    } catch (_) {
      if (mounted) setState(() => _error = l.errorGeneric);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _next() {
    if (!mounted) return;
    setState(() {
      _index++;
      _selected = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final language = currentLanguage(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.appTitle),
        actions: const [LanguageSwitcher()],
      ),
      body: FutureBuilder<List<QuestionView>>(
        future: _questions,
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text(l.errorGeneric));
          if (!snapshot.hasData)
            return const Center(child: CircularProgressIndicator());
          final questions = snapshot.data!;
          if (questions.isEmpty)
            return Center(child: Text(l.studentNoQuestions));
          if (_index >= questions.length) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(l.studentAllDone, textAlign: TextAlign.center),
              ),
            );
          }
          final q = questions[_index];
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Text(
                    l.studentQuestionProgress(_index + 1, questions.length),
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    q.prompt.of(language),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  for (final option in q.options)
                    Card(
                      color: option.id == _selected
                          ? Theme.of(context).colorScheme.primaryContainer
                          : null,
                      child: ListTile(
                        leading: Icon(
                          option.id == _selected
                              ? Icons.check_circle
                              : Icons.circle_outlined,
                        ),
                        title: Text(option.text.of(language)),
                        onTap: _busy
                            ? null
                            : () => setState(() => _selected = option.id),
                      ),
                    ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _selected == null || _busy
                        ? null
                        : () => _submit(q),
                    child: Text(l.studentSubmit),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
