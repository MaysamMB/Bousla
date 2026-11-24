import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../l10n/app_localizations.dart';

/// QR code for the join link, to show or project in class. It contains only
/// the public link with the session code, never anything personal
/// (docs/architecture.md §10).
class JoinQr extends StatelessWidget {
  const JoinQr({super.key, required this.link, required this.code});

  final String link;
  final String code;

  static const _size = 200.0;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      children: [
        _QrBox(link: link, size: _size, label: l.instructorQrLabel(code)),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => _FullScreenQr(link: link, code: code),
          ),
          icon: const Icon(Icons.fullscreen),
          label: Text(l.instructorQrFullScreen),
        ),
      ],
    );
  }
}

/// Black on white whatever the theme: phone cameras need the contrast.
class _QrBox extends StatelessWidget {
  const _QrBox({required this.link, required this.size, required this.label});

  final String link;
  final double size;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        color: Colors.white,
        padding: const EdgeInsets.all(12),
        child: QrImageView(
          data: link,
          size: size,
          backgroundColor: Colors.white,
          errorCorrectionLevel: QrErrorCorrectLevel.M,
          semanticsLabel: label,
        ),
      );
}

/// Large QR and code for projecting to the class.
class _FullScreenQr extends StatelessWidget {
  const _FullScreenQr({required this.link, required this.code});

  final String link;
  final String code;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final screen = MediaQuery.sizeOf(context);
    final side = (screen.shortestSide * 0.6).clamp(200.0, 520.0);
    return Dialog.fullscreen(
      backgroundColor: Colors.white,
      child: Stack(
        children: [
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _QrBox(link: link, size: side, label: l.instructorQrLabel(code)),
                const SizedBox(height: 16),
                // Codes are left-to-right even in the Arabic UI.
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: Text(
                    code,
                    style: Theme.of(context).textTheme.displayMedium?.copyWith(
                          color: Colors.black,
                          letterSpacing: 6,
                        ),
                  ),
                ),
              ],
            ),
          ),
          PositionedDirectional(
            top: 16,
            end: 16,
            child: IconButton(
              tooltip: l.instructorQrClose,
              icon: const Icon(Icons.close, color: Colors.black),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }
}
