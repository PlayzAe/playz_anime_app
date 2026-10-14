import 'services/downloader.dart';
import 'dart:async';

import 'services/native.dart';
import 'sources/manga/extensions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'services/anilist.dart';
import 'services/net.dart';
import 'services/paths.dart';
import 'services/prefs.dart';
import 'services/store.dart';
import 'theme/accent.dart';

/// Boot order matters and is deliberate:
///
///   1. directories, because everything below writes into them
///   2. preferences, which hold the cookie jar on web
///   3. the cookie jar, before the first request can be made
///   4. the store, which is the single source of truth for settings
///   5. the settings that change how *other* services behave — adult filtering,
///      the CORS proxy, a Cloudflare clearance cookie — before any screen can
///      ask for data
///
/// Doing this in `main` rather than in a splash widget means the first frame is
/// already correct: no flash of the wrong accent, no request made with the
/// wrong user agent.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Paths.i.init();
  await Prefs.i.init();

  // ── Cookies ───────────────────────────────────────────────────────────────
  // A `cf_clearance` cookie has to outlive the process, or a Cloudflare-gated
  // source asks for it again on every launch.
  final savedJar = Prefs.i.getJson('cookies');
  if (savedJar != null) Net.i.jar.loadJson(savedJar);
  Net.i.onCookiesChanged = () {
    // Fire and forget: this runs on every Set-Cookie and must never stall a
    // request.
    Prefs.i.setJson('cookies', Net.i.jar.toJson());
  };

  await Store.i.init();
  Downloader.i.init();
  Native.wire();
  // Mihon extensions live in the native host; read what is installed.
  unawaited(Extensions.i.refresh());
  final settings = Store.i.settings;

  // ── Settings that reach into other services ───────────────────────────────
  AniList.i.hideAdult = settings.hideAdult;
  AniList.i.onAdultChanged = () {
    Store.i.removeFeedCache();
  };

  Net.i.proxyUrl = settings.proxyUrl;

  // A pasted clearance cookie is scoped to the domain the user typed it for;
  // applying it to every source host would be wrong, so it is stored under the
  // wildcard key the source layer looks up.
  if (settings.cloudflareCookie.isNotEmpty) {
    for (final host in settings.cloudflareHosts) {
      Net.i.jar.paste(host, settings.cloudflareCookie);
    }
  }

  // ── Chrome ────────────────────────────────────────────────────────────────
  // The app is portrait by default; the player and the reader flip to landscape
  // themselves and restore this on the way out.
  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Color(0x00000000),
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarColor: Color(0x00000000),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  if (!kIsWeb) {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  await applyAccentToSystem(AccentKey.parse(Store.i.settings.accent));

  runApp(const PlayzAnimeApp());
}
