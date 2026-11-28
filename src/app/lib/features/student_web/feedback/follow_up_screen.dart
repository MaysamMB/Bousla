import 'dart:async';

import 'package:bousla_engine/bousla_engine.dart';
import 'package:flutter/material.dart';

import '../../../app_services.dart';
import '../../../data/feedback.dart';
import '../../../data/models.dart';
import '../../../data/repositories/follow_up_repository.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/language.dart';
import '../../../shared/text_direction.dart';
import '../../../shared/widgets/language_switcher.dart';

/// "Test my understanding again": the student's own private follow-up on
/// the concepts they ticked, then their results next to the original ones.
///
/// Created and graded without any instructor ([FollowUpRepository]): the
/// browser gets questions and options, and back only right or wrong for
/// its own locked answers. The comparison uses the original feedback's
/// counts and the follow-up's grades, never the ticks.
class FollowUpScreen extends StatefulWidget {
  const FollowUpScreen({
    super.key,
    required this.sessionId,
    required this.participantId,
    required this.feedback,
    required this.reviewedConceptIds,
  });

  /// The original session and the student its feedback belongs to.
  final String sessionId;
  final String participantId;
  final StudentFeedback feedback;

  /// Eligible concepts the student ticked, in the feedback's order. Only
  /// used to start a new attempt (an existing one keeps its concepts).
  final List<String> reviewedConceptIds;

  @override
  State<FollowUpScreen> createState() => _FollowUpScreenState();
}

/// What the screen shows.
enum _Stage { loading, unavailable, error, answering, results }

class _FollowUpScreenState extends State<FollowUpScreen> {
  var _stage = _Stage.loading;
  FollowUpProblem? _problem;
  FollowUpAttempt? _attempt;
  var _questions = const <QuestionView>[];
  var _done = <QuestionRef>{};
  FollowUpComparison? _comparison;
  String? _selected;
  var _busy = false;
  var _answerError = false;
  var _started = false;

  FollowUpRepository get _repo => ServicesScope.of(context).followUps!;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _load();
    }
  }

  void _show(_Stage stage, [FollowUpProblem? problem]) {
    if (!mounted) return;
    setState(() {
      _stage = stage;
      _problem = problem;
    });
  }

  /// Starts or resumes the attempt. Safe to call again (retry): the attempt
  /// ID is fixed per student and session, so nothing is duplicated.
  Future<void> _load() async {
    _show(_Stage.loading);
    final services = ServicesScope.of(context);
    final language = currentLanguage(context);
    try {
      // The comparison is only valid for the student the feedback belongs
      // to. Another account in this browser: no attempt, no comparison.
      final uid = await services.auth.ensureParticipant();
      if (uid != widget.participantId) {
        return _show(_Stage.unavailable, FollowUpProblem.notOwner);
      }
      var attempt = await _repo.findAttempt(widget.sessionId);
      if (attempt == null) {
        final concepts = widget.reviewedConceptIds;
        if (concepts.isEmpty) {
          return _show(_Stage.unavailable, FollowUpProblem.notEligible);
        }
        final session = await services.sessions
            .watchSession(widget.sessionId)
            .first
            .timeout(const Duration(seconds: 20));
        attempt = await _repo.startAttempt(
          session: session,
          feedback: widget.feedback,
          conceptIds: concepts,
          language: language,
        );
      }
      _attempt = attempt;
      _questions = await _repo.questions(attempt);
      _done = await _repo.graded(attempt);
      if (_questions.isEmpty) {
        return _show(_Stage.unavailable, FollowUpProblem.noQuestions);
      }
      if (attempt.status == FollowUpStatus.finished || _next == null) {
        await _finish();
      } else {
        _show(_Stage.answering);
      }
    } on FollowUpUnavailable catch (e) {
      _show(_Stage.unavailable, e.problem);
    } catch (_) {
      _show(_Stage.error);
    }
  }

  QuestionView? get _next {
    for (final q in _questions) {
      if (!_done.contains(QuestionRef(q.id, q.version))) return q;
    }
    return null;
  }

  Future<void> _submit(QuestionView q) async {
    final option = _selected;
    if (option == null || _busy) return;
    setState(() {
      _busy = true;
      _answerError = false;
    });
    try {
      final ref = QuestionRef(q.id, q.version);
      await _repo.answer(_attempt!, ref, option);
      _done = {..._done, ref};
      _selected = null;
      if (_next == null) {
        await _finish();
      }
    } catch (_) {
      // The answer may be stored already; sending again is safe.
      _answerError = true;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finish() async {
    try {
      _attempt = await _repo.finish(_attempt!);
      final grades = await _repo.grades(_attempt!);
      final before = {
        for (final c in widget.feedback.concepts)
          c.conceptId: Tally(c.correct, c.attempts),
      };
      _comparison = compareFollowUp(
        concepts: _attempt!.conceptIds,
        before: before,
        grades: grades,
      );
      _show(_Stage.results);
    } catch (_) {
      _show(_Stage.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final Widget body = switch (_stage) {
      _Stage.loading => const Center(child: CircularProgressIndicator()),
      _Stage.unavailable => _Message(
          key: const ValueKey('follow-up-unavailable'),
          text: switch (_problem) {
            FollowUpProblem.noQuestions => l.studentFollowUpNoQuestions,
            FollowUpProblem.notOwner => l.studentFollowUpNotOwner,
            _ => l.studentFollowUpNotEligible,
          },
        ),
      _Stage.error => _Message(
          key: const ValueKey('follow-up-error'),
          text: l.studentFollowUpError,
          action: FilledButton(
            key: const ValueKey('follow-up-retry'),
            onPressed: _load,
            child: Text(l.studentFollowUpRetry),
          ),
        ),
      _Stage.answering => _answering(context),
      _Stage.results => _ResultsView(
          comparison: _comparison!,
          feedback: widget.feedback,
        ),
    };
    return Scaffold(
      appBar: AppBar(
        title: Text(_stage == _Stage.results
            ? l.studentFollowUpResultsTitle
            : l.studentFollowUpTitle),
        actions: const [LanguageSwitcher()],
      ),
      body: body,
    );
  }

  Widget _answering(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final language = currentLanguage(context);
    final q = _next!;
    final index = _questions.indexOf(q);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(
          key: ValueKey('follow-up-q-${q.id}'),
          padding: const EdgeInsets.all(24),
          children: [
            if (index == 0 && _done.isEmpty) ...[
              Text(l.studentFollowUpIntro, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 16),
            ],
            Text(
              l.studentQuestionProgress(index + 1, _questions.length),
              style: theme.textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: _done.length / _questions.length),
            const SizedBox(height: 12),
            Text(
              q.prompt.of(language),
              style: theme.textTheme.titleLarge,
              textDirection: textDirectionOf(q.prompt.of(language)),
              textAlign: screenAlign(context),
            ),
            const SizedBox(height: 16),
            for (final option in q.options)
              Card(
                color: option.id == _selected
                    ? theme.colorScheme.primaryContainer
                    : null,
                child: ListTile(
                  key: ValueKey('follow-up-option-${option.id}'),
                  selected: option.id == _selected,
                  leading: Icon(option.id == _selected
                      ? Icons.check_circle
                      : Icons.circle_outlined),
                  title: Text(
                    option.text.of(q.optionLanguageFor(language)),
                    textDirection: textDirectionOf(
                        option.text.of(q.optionLanguageFor(language))),
                    textAlign: screenAlign(context),
                  ),
                  onTap: _busy
                      ? null
                      : () => setState(() => _selected = option.id),
                ),
              ),
            if (_answerError) ...[
              const SizedBox(height: 12),
              Text(
                l.studentFollowUpError,
                key: const ValueKey('follow-up-answer-error'),
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              height: 48,
              child: FilledButton(
                key: const ValueKey('follow-up-submit'),
                onPressed: _selected == null || _busy ? null : () => _submit(q),
                child: _busy
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l.studentSubmit),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// [text] kept left to right inside a right-to-left line (a signed number).
String _ltr(String text) =>
    '${String.fromCharCode(0x2066)}$text${String.fromCharCode(0x2069)}';

class _Message extends StatelessWidget {
  const _Message({super.key, required this.text, this.action});

  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(text, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  if (action case final a?) a,
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(l.studentFollowUpBack),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The follow-up results: a summary, then each tested concept before and
/// after, in cautious words.
class _ResultsView extends StatelessWidget {
  const _ResultsView({required this.comparison, required this.feedback});

  final FollowUpComparison comparison;
  final StudentFeedback feedback;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final language = currentLanguage(context);
    final names = {
      for (final c in feedback.concepts) c.conceptId: c.name.of(language),
    };
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Card(
              key: const ValueKey('follow-up-summary'),
              color: theme.colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  l.studentFollowUpSummary(
                    comparison.assessed,
                    comparison.appearsImproved.length,
                    comparison.mayStillNeedReview.length,
                  ),
                  style: theme.textTheme.titleSmall,
                ),
              ),
            ),
            const SizedBox(height: 8),
            for (final c in comparison.concepts)
              _ConceptResult(
                key: ValueKey('follow-up-concept-${c.conceptId}'),
                result: c,
                name: names[c.conceptId] ?? c.conceptId,
              ),
            const SizedBox(height: 12),
            Text(l.studentFollowUpCaution, style: theme.textTheme.bodySmall),
            const SizedBox(height: 20),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: OutlinedButton.icon(
                key: const ValueKey('follow-up-back'),
                onPressed: () => Navigator.of(context).pop(),
                icon: const BackButtonIcon(),
                label: Text(l.studentFollowUpBack),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConceptResult extends StatelessWidget {
  const _ConceptResult({super.key, required this.result, required this.name});

  final ConceptComparison result;
  final String name;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final r = result;
    final (icon, color, words) = switch (r.change) {
      FollowUpChange.appearsImproved => (
          Icons.trending_up,
          scheme.primary,
          l.studentFollowUpImproved
        ),
      FollowUpChange.aboutTheSame => (
          Icons.trending_flat,
          scheme.onSurfaceVariant,
          l.studentFollowUpSame
        ),
      FollowUpChange.appearsLower => (
          Icons.trending_down,
          scheme.tertiary,
          l.studentFollowUpLower
        ),
      FollowUpChange.noNewEvidence => (
          Icons.help_outline,
          scheme.outline,
          l.studentFollowUpNoNew
        ),
      FollowUpChange.noOriginalEvidence => (
          Icons.help_outline,
          scheme.outline,
          l.studentFollowUpNoOriginal
        ),
    };
    final points = r.differencePoints;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            Text(r.before.attempts == 0
                ? l.studentFollowUpBeforeNone
                : l.studentFollowUpBefore(r.before.correct, r.before.attempts)),
            Text(r.after.attempts == 0
                ? l.studentFollowUpAfterNone
                : l.studentFollowUpAfter(r.after.correct, r.after.attempts)),
            if (points != null)
              // Digits and sign read left to right in both languages.
              Text(
                l.studentFollowUpDifference(
                    _ltr('${points > 0 ? '+' : ''}$points')),
                key: ValueKey('follow-up-diff-${r.conceptId}'),
              ),
            const SizedBox(height: 6),
            // Icon + words: never colour alone.
            Row(
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(words,
                      style:
                          theme.textTheme.bodyMedium?.copyWith(color: color)),
                ),
              ],
            ),
            if (r.mayStillNeedReview) ...[
              const SizedBox(height: 6),
              Chip(
                key: ValueKey('follow-up-review-${r.conceptId}'),
                avatar: const Icon(Icons.replay, size: 16),
                label: Text(l.studentFollowUpStillReview),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
