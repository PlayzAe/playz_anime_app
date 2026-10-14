import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import 'log.dart';

/// The app's link state: up or down, and separately whether the link we are on
/// costs money.
///
/// The desktop asked Electron `net.isOnline()` once per call (`app:online`,
/// read by `SetupStatus.online` and the offline chip) and treated the answer as
/// truth. `connectivity_plus` reports interface state, which is the closest
/// equivalent a phone has — with the standing caveat that a captive portal
/// reports as connected. The port keeps the two transitions the original had
/// (`online` → true, `online` → false) and keeps the flag advisory: nothing
/// gates playback on it, because the offline player has to work when the OS is
/// wrong.
///
/// A `ChangeNotifier` because the offline chip and the downloads queue both
/// watch it; it fires on link changes only, which is a handful of times a day,
/// so it is safe to listen to from the shell.
class NetWatch extends ChangeNotifier {
  NetWatch._();

  static final NetWatch i = NetWatch._();

  final Log _log = Log('netwatch');

  StreamSubscription<List<ConnectivityResult>>? _sub;
  bool _started = false;
  bool _online = true;
  bool _metered = false;

  /// False once the platform says every transport is down.
  ///
  /// Starts true on purpose. `navigator.onLine` was true before any event on
  /// the desktop, and starting false would flash the offline banner on every
  /// cold start while the first platform reply is still in flight. A wrong
  /// "online" costs a failed request that already has a retry; a wrong
  /// "offline" costs a banner and a disabled button.
  bool get online => _online;

  /// True when the current link rides on somebody's data plan — mobile, or a
  /// tethered path — so Settings → "only download on wifi" holds the queue.
  ///
  /// This is the honest ceiling of the plugin: `connectivity_plus` sees the
  /// transport, not Android's `NetworkCapabilities.METERED`, so a phone acting
  /// as a hotspot reads as `wifi` and lands here as unmetered. `dataSaver` is
  /// the switch for that case; this one answers the question the settings row
  /// actually asks, which is "am I about to spend mobile data".
  bool get metered => _metered;

  /// Starts the watcher. Called once from `main()` before `runApp`.
  ///
  /// Idempotent, like every other service's `init`, so a hot restart or a
  /// second caller cannot end up with two subscriptions to the same channel.
  Future<void> init() async {
    if (_started) return;
    _started = true;

    try {
      _apply(await Connectivity().checkConnectivity());
    } catch (err) {
      // No plugin on this platform, or the channel blew up. Keep the optimistic
      // default rather than reporting a link state we do not have.
      _log.warn('could not read the initial link state', err);
    }

    _sub = Connectivity().onConnectivityChanged.listen(
      _apply,
      onError: (Object err) {
        // A stream error must never take the shell down; the last known state
        // stands until a real event arrives.
        _log.warn('link state stream failed', err);
      },
    );
  }

  /// Re-reads the link once, for a caller that has to be sure before it starts
  /// something expensive. The stream already covers the transitions, so this is
  /// for the "I woke up from doze and I am about to open a socket" case.
  Future<void> refresh() async {
    try {
      _apply(await Connectivity().checkConnectivity());
    } catch (err) {
      _log.warn('could not refresh the link state', err);
    }
  }

  /// The rule `Settings.downloadOnlyOnWifi` asks about, kept here so the
  /// downloads queue and the Settings row cannot drift apart.
  ///
  /// Offline is never allowed, whatever the switch says — a held job waits,
  /// it does not fail.
  bool allowsDownload({required bool onlyOnWifi}) => _online && !(onlyOnWifi && _metered);

  void _apply(List<ConnectivityResult> results) {
    final nextOnline = _onlineOf(results);
    final nextMetered = nextOnline && _meteredOf(results);

    // Some platforms re-announce the same radio state; a rebuild of the shell
    // for a no-op change is exactly the kind of tick the performance contract
    // is about.
    if (nextOnline == _online && nextMetered == _metered) return;

    _online = nextOnline;
    _metered = nextMetered;
    _log.info('link is ${_online ? 'up' : 'down'}${_metered ? ' (metered)' : ''}');
    notifyListeners();
  }

  /// An empty list is not a promise of anything, so it counts as offline —
  /// `contains(none)` alone misses the case where a platform reports no
  /// transports at all.
  static bool _onlineOf(List<ConnectivityResult> results) {
    if (results.isEmpty) return false;
    for (final r in results) {
      if (r != ConnectivityResult.none) return true;
    }
    return false;
  }

  /// Mobile is a data plan. Bluetooth and `other` are tethering paths, which
  /// spend either the phone's own plan or a hotspot's — treat both as metered.
  /// Wifi and ethernet are what the settings switch calls free. A VPN is not
  /// decidable on its own, but Android reports the transport underneath it
  /// alongside, so a VPN over mobile still finds `mobile` in the list.
  static bool _meteredOf(List<ConnectivityResult> results) {
    for (final r in results) {
      if (r == ConnectivityResult.mobile ||
          r == ConnectivityResult.bluetooth ||
          r == ConnectivityResult.other) {
        return true;
      }
    }
    return false;
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
