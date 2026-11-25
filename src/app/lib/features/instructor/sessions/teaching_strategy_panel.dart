import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import 'teaching_actions.dart';
import 'teaching_strategy.dart';

/// The parent keys this widget by current action/evidence and locale. A
/// changed snapshot disposes the old request UI; late results are ignored.
class TeachingStrategyPanel extends StatefulWidget {
  const TeachingStrategyPanel({
    super.key,
    required this.action,
    required this.conceptName,
    this.relatedName,
    this.choose,
  });

  final TeachingAction action;
  final String conceptName;
  final String? relatedName;
  final TeachingStrategyChooser? choose;

  @override
  State<TeachingStrategyPanel> createState() => _TeachingStrategyPanelState();
}

class _TeachingStrategyPanelState extends State<TeachingStrategyPanel> {
  bool _busy = false;
  bool _reviewed = false;
  TeachingStrategyResult? _result;

  Future<void> _request() async {
    if (_busy || _result != null || widget.choose == null) return;
    setState(() => _busy = true);
    final result = await resolveTeachingStrategy(
      kind: widget.action.kind,
      conceptName: widget.conceptName,
      relatedName: widget.relatedName,
      choose: widget.choose,
      language: Localizations.localeOf(context).languageCode,
    );
    if (!mounted) return;
    setState(() { _result = result; _busy = false; });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final result = _result ?? TeachingStrategyResult(
      allowedStrategies(widget.action.kind).first,
      aiSelected: false,
    );
    final tactic = switch (result.strategy) {
      TeachingStrategy.workedExample => l.instructorStrategyWorked,
      TeachingStrategy.conceptLink => l.instructorStrategyLink,
      TeachingStrategy.contrastExamples => l.instructorStrategyContrast,
      TeachingStrategy.peerExplanation => l.instructorStrategyPeer,
      TeachingStrategy.quickCheck => l.instructorStrategyCheck,
      TeachingStrategy.explainReasoning => l.instructorStrategyReason,
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l.instructorStrategyTitle,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(widget.conceptName,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            Text(result.aiSelected
                ? l.instructorStrategyAiLabel
                : l.instructorStrategyRuleLabel),
            const SizedBox(height: 8),
            Text(tactic),
            const SizedBox(height: 8),
            Text(l.instructorStrategyNote),
            if (result.draft case final draft?) ...[
              const SizedBox(height: 12),
              Text(l.instructorDraftExample,
                  style: Theme.of(context).textTheme.titleSmall),
              SelectableText(draft.example),
              const SizedBox(height: 8),
              Text(l.instructorDraftQuestion,
                  style: Theme.of(context).textTheme.titleSmall),
              SelectableText(draft.question),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _reviewed,
                onChanged: (value) => setState(() => _reviewed = value ?? false),
                title: Text(l.instructorDraftReview),
              ),
              Text(_reviewed ? l.instructorDraftReviewed : l.instructorDraftUnreviewed),
            ],
            if (widget.choose == null)
              Text(l.instructorStrategyOffline)
            else if (_result == null) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _busy ? null : _request,
                icon: _busy
                    ? const SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.auto_awesome),
                label: Text(_busy ? l.instructorStrategyWorking
                    : l.instructorStrategyAsk),
              ),
            ] else if (!result.aiSelected)
              Text(l.instructorStrategyFallback),
          ],
        ),
      ),
    );
  }
}
