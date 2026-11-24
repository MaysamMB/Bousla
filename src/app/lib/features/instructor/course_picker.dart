import 'package:flutter/material.dart';

import '../../app_services.dart';
import '../../data/models.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/language.dart';

/// The course the instructor's screens work on: the one chosen in
/// [AppServices.selectedCourseId] if it is still in [courses], otherwise the
/// first one. Null when the instructor has no course.
Course? chooseCourse(List<Course> courses, String? selectedId) =>
    courses.where((c) => c.id == selectedId).firstOrNull ??
    courses.firstOrNull;

/// Lets an instructor with several courses choose one. With a single course
/// it shows only its name. The choice is kept in
/// [AppServices.selectedCourseId], so the session and review screens use the
/// same course. Courses are added with `seed --course <folder>`.
class CoursePicker extends StatelessWidget {
  const CoursePicker({
    super.key,
    required this.courses,
    required this.current,
    required this.onChanged,
    this.enabled = true,
  });

  final List<Course> courses;
  final Course current;

  /// Called after the choice is stored; the screen reloads its content.
  final VoidCallback onChanged;

  /// False while a session is running, so it is not mixed with another course.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final language = currentLanguage(context);
    final style = Theme.of(context).textTheme.headlineSmall;
    if (courses.length < 2) {
      return Text(current.name.of(language), style: style);
    }
    return DropdownButtonFormField<String>(
      // A new key when the course changes, so the field shows it.
      key: ValueKey(current.id),
      initialValue: current.id,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: AppLocalizations.of(context).instructorCourseLabel,
        border: const OutlineInputBorder(),
      ),
      items: [
        for (final c in courses)
          DropdownMenuItem(value: c.id, child: Text(c.name.of(language))),
      ],
      onChanged: !enabled
          ? null
          : (id) {
              if (id == null || id == current.id) return;
              ServicesScope.of(context).selectedCourseId.value = id;
              onChanged();
            },
    );
  }
}
