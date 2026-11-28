import 'package:flutter/material.dart';

import '../../../data/repositories/profile_repository.dart';

/// The preset profile pictures: an icon on a colour. No photo is uploaded,
/// so nothing about the student's face is stored.
const profileAvatars = <(IconData, Color)>[
  (Icons.auto_stories_rounded, Color(0xFF0E7C6A)),
  (Icons.explore_rounded, Color(0xFF1E5AA8)),
  (Icons.lightbulb_rounded, Color(0xFFB7791F)),
  (Icons.rocket_launch_rounded, Color(0xFF8E44AD)),
  (Icons.psychology_rounded, Color(0xFFC0392B)),
  (Icons.code_rounded, Color(0xFF2C3E50)),
  (Icons.storage_rounded, Color(0xFF16A085)),
  (Icons.insights_rounded, Color(0xFFD35400)),
  (Icons.local_florist_rounded, Color(0xFF27AE60)),
  (Icons.star_rounded, Color(0xFFB8860B)),
  (Icons.palette_rounded, Color(0xFFAD1457)),
  (Icons.public_rounded, Color(0xFF00838F)),
];

/// The student's picture: their preset, else the first letter of their
/// name, else a person icon.
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({super.key, required this.info, this.radius = 28});

  final ProfileInfo info;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final a = info.avatar;
    if (a != null && a >= 0 && a < profileAvatars.length) {
      final (icon, color) = profileAvatars[a];
      return CircleAvatar(
        radius: radius,
        backgroundColor: color,
        child: Icon(icon, color: Colors.white, size: radius),
      );
    }
    final name = info.displayName?.trim() ?? '';
    return CircleAvatar(
      radius: radius,
      backgroundColor: scheme.primaryContainer,
      foregroundColor: scheme.onPrimaryContainer,
      child: name.isEmpty
          ? Icon(Icons.person_rounded, size: radius)
          : Text(
              name.characters.first.toUpperCase(),
              style: TextStyle(fontSize: radius * 0.8),
            ),
    );
  }
}
