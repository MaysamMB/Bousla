import 'package:bousla_engine/bousla_engine.dart';
import 'package:flutter/widgets.dart';

/// The engine [Language] matching the current UI locale.
Language currentLanguage(BuildContext context) =>
    Localizations.localeOf(context).languageCode == 'ar'
    ? Language.ar
    : Language.en;
