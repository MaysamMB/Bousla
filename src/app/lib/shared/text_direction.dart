import 'package:flutter/widgets.dart';

final _arabicLetter = RegExp(r'[؀-ۿ]');

/// The reading direction of [text] itself, whatever the UI language: with
/// any Arabic letter right-to-left, otherwise left-to-right. So SQL or an
/// English sentence keeps its ";" and brackets in place inside the Arabic
/// interface ("SELECT … gpa > 3;" was shown as ";> 3").
TextDirection textDirectionOf(String text) =>
    _arabicLetter.hasMatch(text) ? TextDirection.rtl : TextDirection.ltr;

/// Aligned with the rest of the screen (right in Arabic, left in English),
/// whatever direction the text itself reads in.
TextAlign screenAlign(BuildContext context) =>
    Directionality.of(context) == TextDirection.rtl
        ? TextAlign.right
        : TextAlign.left;
