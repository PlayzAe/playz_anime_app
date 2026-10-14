import 'dart:async';

import 'package:flutter/material.dart' hide Ink;

import '../app.dart';
import '../models/media.dart';
import '../services/anilist.dart';
import '../services/format.dart';
import '../services/store.dart';
import '../theme/tokens.dart';
import '../ui/kit.dart';
import '../widgets/pz_image.dart';
import 'series_view.dart';
import 'watch_view.dart';

/// Airing schedule. Port of `Schedule.tsx`: a week strip, each day's episodes
/// in local time, a live countdown for what's next.
class ScheduleView extends StatefulWidget {
  const ScheduleView({super.key});

  @override
  State<ScheduleView> createState() => _ScheduleViewState();
}

class _ScheduleViewState extends State<ScheduleView> {
  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  late final DateTime _start = _midnight(DateTime.now());
  int _day = 0;
  List<AiringItem>? _items;
  Object? _error;
  bool _mine = false;
  Timer? _tick;

  static DateTime _midnight(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  void initState() {
    super.initState();
    _load();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _load({bool force = false}) async {
    setState(() => _error = null);
    try {
      final from = _start.millisecondsSinceEpoch ~/ 1000;
      final to = _start.add(const Duration(days: 7)).millisecondsSinceEpoch ~/ 1000;
      final items = await AniList.i.schedule(from, to, force: force);
      items.sort((a, b) => a.airingAt.compareTo(b.airingAt));
      if (mounted) setState(() => _items = items);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final day = _start.add(Duration(days: _day));
    final end = day.add(const Duration(days: 1));
    final mine = Store.i.library().map((e) => e.media.id).toSet();
    final list = (_items ?? const <AiringItem>[]).where((a) {
      final t = DateTime.fromMillisecondsSinceEpoch(a.airingAt * 1000);
      return !t.isBefore(day) && t.isBefore(end) && (!_mine || mine.contains(a.media.id));
    }).toList();
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final nextIdx = list.indexWhere((a) => a.airingAt > now);

    return Column(children: [
      TabTopBar(
        title: 'Schedule',
        trailing: Pressable(
          onTap: () => setState(() => _mine = !_mine),
          child: AnimatedContainer(
            duration: kMed,
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _mine ? accentOf(context) : Ink.ink2,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _mine ? accentOf(context) : Lines.line2),
            ),
            child: Text('My list', style: body(13, weight: FontWeight.w700, color: _mine ? Seal.accentInk : Paper.paper2)),
          ),
        ),
      ),
      SizedBox(
        height: 70,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          itemCount: 7,
          itemBuilder: (c, i) {
            final d = _start.add(Duration(days: i));
            final on = i == _day;
            final count = (_items ?? const <AiringItem>[]).where((a) {
              final t = DateTime.fromMillisecondsSinceEpoch(a.airingAt * 1000);
              return !t.isBefore(d) && t.isBefore(d.add(const Duration(days: 1))) && (!_mine || mine.contains(a.media.id));
            }).length;
            return Pressable(
              onTap: () => setState(() => _day = i),
              child: AnimatedContainer(
                duration: kMed,
                curve: kEase,
                width: 58,
                margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                decoration: BoxDecoration(
                  color: on ? Paper.paper : Ink.ink1,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: on ? Paper.paper : Lines.line),
                ),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(i == 0 ? 'Today' : _days[d.weekday - 1], style: body(11, weight: FontWeight.w700, color: on ? Ink.ink0 : Paper.paper3)),
                  Text('${d.day}', style: display(22, color: on ? Ink.ink0 : Paper.paper)),
                  Text(_items == null ? ' ' : '$count', style: body(10, color: on ? Ink.ink2 : Paper.paper4)),
                ]),
              ),
            );
          },
        ),
      ),
      const Divider(height: 1, color: Lines.line),
      Expanded(
        child: _error != null && _items == null
            ? Center(child: StatePanel(title: 'Couldn’t load the schedule', message: '$_error', icon: 'offline', action: 'Try again', onAction: () => _load(force: true)))
            : _items == null
                ? ListView(padding: const EdgeInsets.all(kGutter), children: [
                    for (var i = 0; i < 6; i++) const Padding(padding: EdgeInsets.only(bottom: 10), child: Skeleton(height: 84)),
                  ])
                : RefreshIndicator(
                    color: accentOf(context),
                    onRefresh: () => _load(force: true),
                    child: list.isEmpty
                        ? ListView(children: [
                            StatePanel(
                              title: _mine ? 'Nothing from your list airs this day' : 'Nothing airs this day',
                              message: _mine ? 'Turn off “My list” to see everything.' : null,
                              icon: 'schedule',
                            ),
                          ])
                        : ListView.builder(
                            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                            padding: const EdgeInsets.fromLTRB(kGutter, 12, kGutter, 32),
                            itemCount: list.length,
                            itemBuilder: (c, i) => FadeIn(
                              key: ValueKey('${_day}_${list[i].id}'),
                              delay: Duration(milliseconds: 25 * (i % 10)),
                              child: _Row(item: list[i], now: now, isNext: i == nextIdx),
                            ),
                          ),
                  ),
      ),
    ]);
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.item, required this.now, required this.isNext});

  final AiringItem item;
  final int now;
  final bool isNext;

  @override
  Widget build(BuildContext context) {
    final m = item.media;
    final t = DateTime.fromMillisecondsSinceEpoch(item.airingAt * 1000);
    final aired = item.airingAt <= now;
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    final accent = accentOf(context);
    return Pressable(
      scale: 0.98,
      onTap: () => go(context, aired ? WatchView(mediaId: m.id, episode: item.episode) : SeriesView(mediaId: m.id)),
      onLongPress: () => go(context, SeriesView(mediaId: m.id)),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isNext ? Ink.ink2 : Ink.ink1,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isNext ? accent : Lines.line),
        ),
        child: Row(children: [
          SizedBox(
            width: 50,
            child: Column(children: [
              Text('$hh:$mm', style: body(14, weight: FontWeight.w800, color: aired ? Paper.paper3 : Paper.paper)),
              const SizedBox(height: 2),
              Text(aired ? 'Aired' : 'Soon', style: body(10.5, color: aired ? Paper.paper4 : accent, weight: FontWeight.w700)),
            ]),
          ),
          const SizedBox(width: 8),
          SizedBox(width: 46, child: AspectRatio(aspectRatio: 2 / 3, child: PzImage(url: Fmt.coverOf(m), radius: BorderRadius.circular(5)))),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(Fmt.titleOf(m, lang: Store.i.settings.titleLanguage), maxLines: 2, overflow: TextOverflow.ellipsis, style: body(14, weight: FontWeight.w700, height: 1.2)),
              const SizedBox(height: 3),
              Text(
                aired
                    ? 'Episode ${item.episode}${m.episodes != null ? ' of ${m.episodes}' : ''} · tap to watch'
                    : 'Episode ${item.episode} in ${Fmt.countdown(item.airingAt - now)}',
                style: body(12, color: aired ? Paper.paper3 : Paper.paper2),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
