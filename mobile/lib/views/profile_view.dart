import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' hide Ink;
import 'package:share_plus/share_plus.dart';

import '../models/local.dart';
import '../services/downloader.dart';
import '../services/store.dart';
import '../theme/tokens.dart';
import '../ui/kit.dart';
import '../widgets/pz_icon.dart';

/// The round avatar shown in the top bar and on the profile page.
class Avatar extends StatelessWidget {
  const Avatar({super.key, this.size = 34});

  final double size;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Store.i,
        builder: (c, _) {
          final p = Store.i.profile;
          final bytes = _decode(p?.avatar);
          final name = (p?.name ?? '').trim();
          return Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Ink.ink3,
              border: Border.all(color: accentOf(c), width: 1.5),
              image: bytes == null ? null : DecorationImage(image: MemoryImage(bytes), fit: BoxFit.cover),
            ),
            alignment: Alignment.center,
            child: bytes != null
                ? null
                : name.isEmpty
                    ? PzIcon('profile', size: size * 0.5, color: Paper.paper2)
                    : Text(name[0].toUpperCase(), style: display(size * 0.5)),
          );
        },
      );

  static final Map<String, Uint8List> _cache = {};

  static Uint8List? _decode(String? dataUrl) {
    if (dataUrl == null || !dataUrl.startsWith('data:')) return null;
    return _cache[dataUrl] ??= base64Decode(dataUrl.substring(dataUrl.indexOf(',') + 1));
  }
}

/// Profile: name, picture, and the backup file. Desktop `components/Profile.tsx`.
class ProfileView extends StatefulWidget {
  const ProfileView({super.key});

  @override
  State<ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends State<ProfileView> {
  late final _name = TextEditingController(text: Store.i.profile?.name ?? '');
  late final _tag = TextEditingController(text: Store.i.profile?.tagline ?? '');

  @override
  void dispose() {
    _save();
    _name.dispose();
    _tag.dispose();
    super.dispose();
  }

  Profile get _p =>
      Store.i.profile ?? Profile(id: 'p${DateTime.now().millisecondsSinceEpoch}', name: '', createdAt: DateTime.now().millisecondsSinceEpoch);

  void _save({String? avatar, bool clearAvatar = false}) {
    final p = _p;
    Store.i.setProfile(Profile(
      id: p.id,
      name: _name.text.trim(),
      createdAt: p.createdAt,
      avatar: clearAvatar ? null : (avatar ?? p.avatar),
      tagline: _tag.text.trim().isEmpty ? null : _tag.text.trim(),
      favorites: p.favorites,
    ));
  }

  Future<void> _pickPicture() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    final bytes = res?.files.firstOrNull?.bytes;
    if (bytes == null) return;
    try {
      // Square-ish 256 px PNG keeps the profile file small.
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 256);
      final frame = await codec.getNextFrame();
      final png = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      if (png == null) return;
      _save(avatar: 'data:image/png;base64,${base64Encode(png.buffer.asUint8List())}');
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) toast(context, 'That picture couldn’t be read');
    }
  }

  Future<void> _export() async {
    _save();
    final data = {
      ...Store.i.exportProfile().toJson(),
      'settings': Store.i.settings.toJson()..removeWhere((k, _) => const {'cloudflareCookie', 'cloudflareCookieHosts', 'proxyUrl'}.contains(k)),
    };
    final name = (_p.name.isEmpty ? 'profile' : _p.name).replaceAll(RegExp(r'[^\w\- ]'), '').trim();
    try {
      final dir = await Downloader.i.folder();
      final path = '$dir${Platform.pathSeparator}PlayzAnime-$name.playzanime';
      await File(path).writeAsString(jsonEncode(data));
      if (!mounted) return;
      toast(context, 'Saved to $path');
      await SharePlus.instance.share(ShareParams(files: [XFile(path)], text: 'My PlayzAnime profile'));
    } catch (e) {
      if (mounted) toast(context, 'Couldn’t save the file: $e');
    }
  }

  Future<void> _import() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.any, withData: true);
    final bytes = res?.files.firstOrNull?.bytes;
    if (bytes == null) return;
    try {
      final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      final p = ProfileExport.fromJson(json);
      if (!mounted) return;
      final ok = await confirm(
        context,
        title: 'Restore ${p.profile.name.isEmpty ? 'this profile' : p.profile.name}?',
        message: '${p.library.length} saved titles, ${p.history.length} watched and ${p.reading.length} read merge into this phone. '
            '${json['settings'] != null ? 'Your settings (accent, player, reader) are replaced too.' : ''}',
        action: 'Restore',
      );
      if (!ok) return;
      Store.i.restoreBackup(p, settings: (json['settings'] as Map?)?.cast<String, dynamic>());
      _name.text = Store.i.profile?.name ?? '';
      _tag.text = Store.i.profile?.tagline ?? '';
      if (mounted) {
        setState(() {});
        toast(context, 'Profile restored');
      }
    } catch (e) {
      if (mounted) toast(context, e is ProfileFormatException ? e.message : 'That file isn’t a PlayzAnime profile');
    }
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    final lib = Store.i.library().length;
    final watched = Store.i.history().length;
    final read = Store.i.reading().length;
    InputDecoration deco(String hint) => InputDecoration(
          hintText: hint,
          hintStyle: body(15, color: Paper.paper4),
          filled: true,
          fillColor: Ink.ink2,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        );
    return Scaffold(
      backgroundColor: Ink.ink0,
      body: ListView(padding: EdgeInsets.fromLTRB(kGutter, top + 8, kGutter, 40), children: [
        Row(children: [
          RoundIcon('arrowLeft', filled: false, onTap: () => Navigator.pop(context)),
          const SizedBox(width: 6),
          Text('Profile', style: display(30)),
        ]),
        const SizedBox(height: 18),
        Center(
          child: Pressable(
            onTap: _pickPicture,
            child: Stack(children: [
              const Avatar(size: 104),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(color: accentOf(context), shape: BoxShape.circle, border: Border.all(color: Ink.ink0, width: 3)),
                  child: const Icon(Icons.edit, size: 16, color: Colors.white),
                ),
              ),
            ]),
          ),
        ),
        if (Store.i.profile?.avatar != null)
          Center(
            child: TextButton(
              onPressed: () => setState(() => _save(clearAvatar: true)),
              child: Text('Remove picture', style: body(12.5, color: Paper.paper3)),
            ),
          ),
        const SizedBox(height: 14),
        Text('Name', style: body(13, color: Paper.paper3, weight: FontWeight.w700)),
        const SizedBox(height: 6),
        TextField(controller: _name, style: body(16), decoration: deco('What should PlayzAnime call you?'), onChanged: (_) => _save()),
        const SizedBox(height: 12),
        Text('About you', style: body(13, color: Paper.paper3, weight: FontWeight.w700)),
        const SizedBox(height: 6),
        TextField(controller: _tag, style: body(15), decoration: deco('Favourite genre, current obsession…'), onChanged: (_) => _save()),
        const SizedBox(height: 20),
        Row(children: [
          for (final (n, l) in [(lib, 'Saved'), (watched, 'Watched'), (read, 'Reading')])
            Expanded(
              child: Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(color: Ink.ink1, borderRadius: BorderRadius.circular(10), border: Border.all(color: Lines.line)),
                child: Column(children: [
                  Text('$n', style: display(26)),
                  Text(l, style: body(12, color: Paper.paper3)),
                ]),
              ),
            ),
        ]),
        const SizedBox(height: 22),
        Text('Backup', style: body(18, weight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text('One .playzanime file with your list, history, reading progress and settings. Open it on another phone, or the desktop app, to carry everything over.',
            style: body(12.5, color: Paper.paper3, height: 1.45)),
        const SizedBox(height: 12),
        PzBtn('Export profile', icon: 'share', primary: true, onTap: _export),
        const SizedBox(height: 10),
        PzBtn('Import profile', icon: 'folder', onTap: _import),
      ]),
    );
  }
}
