import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/branding/doh_myot_daw_logo.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await preloadDohMyotDawLogo();
  runApp(const ProviderScope(child: BcnRestaurantApp()));
}
