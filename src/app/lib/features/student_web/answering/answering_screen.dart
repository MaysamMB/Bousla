import 'dart:async';

import 'package:bousla_engine/bousla_engine.dart';
import 'package:flutter/material.dart';

import '../../../app_services.dart';
import '../../../data/models.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/text_direction.dart';
import '../../../shared/language.dart';
import '../../../shared/widgets/language_switcher.dart';
import '../feedback/feedback_screen.dart';

/// One question at a time, in the student's chosen language (owner: student
/// web portal). Switching language mid-way keeps the same question and
/// options; only the text and direction change, and each answer records the
/// language it was shown in. After the last answer it waits for the
/// instructor to publish feedback and then opens [FeedbackScreen]. To do:
/// accessibility review.
class AnsweringScreen extends StatefulWidget {
  const AnsweringScreen({
    super.key,
    required this.session,
    required this.participantId,
  });

  final Session session;
  final String participantId;

  /// Longest wait for the server before telling the student to try again,
  /// instead of leaving the screen frozen on a weak connection.
  static const timeout = Duration(seconds: 20);

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

  /// Approved questions of this session, in the session's order. Uses the
  /// exact versions the session was created with, so an instructor editing a
  /// question during the session does not change it for students.
  ///
  /// After a page reload the student continues at the first question they
  /// have not answered yet.
  Future<List<QuestionView>> _load() async {
    final services = ServicesScope.of(context);
    final (questions, answered) = await (
      services.content.questionsForSession(
        widget.session.courseId,
        widget.session.questions,
      ),
      services.sessions.answeredQuestions(
        widget.session,
        widget.participantId,
      ),
    ).wait.timeout(AnsweringScreen.timeout);
    final firstOpen = questions.indexWhere(
      (q) => !answered.contains(QuestionRef(q.id, q.version)),
    );
    _index = firstOpen == -1 ? questions.length : firstOpen;
    return questions;
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
      await sessions
          .submitResponse(
            widget.session.id,
            Response(
              participantId: widget.participantId,
              questionId: q.id,
              questionVersion: q.version,
              selectedOptionId: _selected!,
              displayLanguage: language,
            ),
          )
          .timeout(AnsweringScreen.timeout);
      _next();
    } on DuplicateAnswerException {
      _next();
    } on SessionClosedException {
      if (mounted) setState(() => _error = l.studentSessionClosed);
    } on TimeoutException {
      // Safe to press again: a second answer to the same question is
      // refused by the server and then skipped here.
      if (mounted) setState(() => _error = l.studentConnectionSlow);
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
    return FutureBuilder<List<QuestionView>>(
      future: _questions,
      builder: (context, snapshot) {
        final questions = snapshot.data;
        final Widget body;
        Widget? submitBar;
        if (snapshot.hasError) {
          body = Center(
            child: Text(
              snapshot.error is TimeoutException
                  ? l.studentConnectionSlow
                  : l.errorGeneric,
              textAlign: TextAlign.center,
            ),
          );
        } else if (questions == null) {
          body = const Center(child: CircularProgressIndicator());
        } else if (questions.isEmpty) {
          body = Center(child: Text(l.studentNoQuestions));
        } else if (_index >= questions.length) {
          body = _ThankYou(
            sessionId: widget.session.id,
            participantId: widget.participantId,
          );
        } else {
          final q = questions[_index];
          body = Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: ListView(
                key: ValueKey(q.id),
                padding: const EdgeInsets.all(24),
                children: [
                  Text(
                    l.studentQuestionProgress(_index + 1, questions.length),
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(value: _index / questions.length),
                  const SizedBox(height: 12),
                  Text(
                    q.prompt.of(language),
                    style: Theme.of(context).textTheme.titleLarge,
                    // A question written in English (or code) reads
                    // left-to-right even in the Arabic interface.
                    textDirection: textDirectionOf(q.prompt.of(language)),
                    textAlign: screenAlign(context),
                  ),
                  const SizedBox(height: 16),
                  // The instructor may hide the options in one language;
                  // then they are shown in the other one, with its own
                  // direction. The question text stays in the UI language.
                  for (final option in q.options)
                    Card(
                      color: option.id == _selected
                          ? Theme.of(context).colorScheme.primaryContainer
                          : null,
                      child: ListTile(
                        selected: option.id == _selected,
                        leading: Icon(
                          option.id == _selected
                              ? Icons.check_circle
                              : Icons.circle_outlined,
                        ),
                        title: _OptionText(
                          option: option,
                          language: q.optionLanguageFor(language),
                        ),
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
                ],
              ),
            ),
          );
          submitBar = SafeArea(
            top: false,
            child: Center(
              heightFactor: 1,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 8,
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton(
                      onPressed: _selected == null || _busy
                          ? null
                          : () => _submit(q),
                      child: _busy
                          ? SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                semanticsLabel: l.studentSubmit,
                              ),
                            )
                          : Text(l.studentSubmit),
                    ),
                  ),
                ),
              ),
            ),
          );
        }
        return Scaffold(
          appBar: AppBar(
            title: Text(l.appTitle),
            actions: const [LanguageSwitcher()],
          ),
          body: body,
          bottomNavigationBar: submitBar,
        );
      },
    );
  }
}

class _OptionText extends StatelessWidget {
  const _OptionText({required this.option, required this.language});

  final OptionView option;
  final Language language;

  @override
  Widget build(BuildContext context) => Text(
    option.text.of(language),
    // Read in its own direction (from the text: SQL in the Arabic options
    // is still left-to-right), but aligned with the rest of the screen.
    textDirection: textDirectionOf(option.text.of(language)),
    textAlign: screenAlign(context),
  );
}

/// "Thank you" after the last answer. Waits for this participant's feedback
/// ([SessionRepository.watchMyFeedback] stays null until the instructor
/// releases it) and then opens it.
class _ThankYou extends StatefulWidget {
  const _ThankYou({required this.sessionId, required this.participantId});

  final String sessionId;
  final String participantId;

  @override
  State<_ThankYou> createState() => _ThankYouState();
}

class _ThankYouState extends State<_ThankYou> {
  StreamSubscription<Object?>? _sub;
  var _opened = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sub ??= ServicesScope.of(context)
        .sessions
        .watchMyFeedback(widget.sessionId, widget.participantId)
        .listen(
      (feedback) {
        if (feedback == null || _opened || !mounted) return;
        _opened = true;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => FeedbackScreen(
              sessionId: widget.sessionId,
              participantId: widget.participantId,
            ),
          ),
        );
      },
      // Waiting for feedback is optional: on an error the thank-you stays.
      onError: (Object _) {},
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l.studentAllDone, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Text(
              l.studentFeedbackWaiting,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
