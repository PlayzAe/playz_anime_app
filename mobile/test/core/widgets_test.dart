import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playzanime/theme/accent.dart';
import 'package:playzanime/ui/kit.dart';

Widget host(Widget child) => PzAccent(key0: AccentKey.shu, child: MaterialApp(home: Scaffold(body: Center(child: child))));

void main() {
  testWidgets('PzToggle flips on tap', (t) async {
    var v = false;
    await t.pumpWidget(host(StatefulBuilder(builder: (c, set) => PzToggle(value: v, onChanged: (n) => set(() => v = n)))));
    await t.tap(find.byType(PzToggle));
    await t.pumpAndSettle();
    expect(v, isTrue);
  });

  testWidgets('Segmented reports the tapped option', (t) async {
    String picked = 'a';
    await t.pumpWidget(host(Segmented<String>(value: 'a', options: const [('a', 'English'), ('b', 'Romaji')], onChanged: (v) => picked = v)));
    await t.tap(find.text('Romaji'));
    await t.pumpAndSettle();
    expect(picked, 'b');
  });

  testWidgets('PzBtn ignores taps while disabled', (t) async {
    var taps = 0;
    await t.pumpWidget(host(Column(mainAxisSize: MainAxisSize.min, children: [
      PzBtn('Live', onTap: () => taps++),
      const PzBtn('Dead'),
    ])));
    await t.tap(find.text('Live'));
    await t.tap(find.text('Dead'));
    await t.pumpAndSettle();
    expect(taps, 1);
  });

  testWidgets('FadeIn ends fully visible', (t) async {
    await t.pumpWidget(host(const FadeIn(child: Text('hi'))));
    await t.pumpAndSettle();
    expect(t.widget<Opacity>(find.ancestor(of: find.text('hi'), matching: find.byType(Opacity)).first).opacity, 1);
  });
}
