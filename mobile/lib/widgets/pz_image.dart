import 'dart:io';

import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../sources/manga/extensions.dart';
import '../sources/manga/providers.dart' show MPage;

import '../services/cache_image.dart';
import '../theme/tokens.dart';

/// A cached network image with bounded memory decode and optional rounded corners.
///
/// Ported from PlayzAnime's desktop artwork component. Automatically passes
/// decode bounds (`memCacheWidth` / `memCacheHeight`) when [width] or [height]
/// are provided so large artwork doesn't blow out mobile RAM.
class PzImage extends StatelessWidget {
  const PzImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.radius,
    this.blurHashColor,
    this.referer,
    this.fade = true,
    this.alignment = Alignment.center,
  });

  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? radius;
  final Color? blurHashColor;
  final String? referer;
  final bool fade;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final placeholderColor = blurHashColor ?? Ink.ink1;

    Widget placeholder(BuildContext context, [String? url]) => ColoredBox(
          color: placeholderColor,
          child: SizedBox(width: width, height: height),
        );

    Widget errorWidget(BuildContext context, String url, Object error) =>
        placeholder(context, url);

    Widget child;
    final trimmed = url.trim();
    if (trimmed.isEmpty) {
      child = placeholder(context);
    } else if (trimmed.startsWith('file://')) {
      // Downloaded chapter pages, unpacked from the CBZ.
      child = Image.file(
        File(trimmed.substring(7)),
        width: width,
        height: height,
        fit: fit,
        alignment: alignment,
        errorBuilder: (ctx, e, _) => placeholder(ctx, trimmed),
      );
    } else {
      // Decode bounds: 2x layout size to remain crisp on high-DPI displays
      final memW = width != null && width!.isFinite && width! > 0 ? (width! * 2).toInt() : null;
      final memH = height != null && height!.isFinite && height! > 0 ? (height! * 2).toInt() : null;

      final headers = referer != null && referer!.isNotEmpty
          ? <String, String>{'Referer': referer!, 'User-Agent': kImageUa}
          : null;

      child = CachedNetworkImage(
        imageUrl: trimmed,
        width: width,
        height: height,
        fit: fit,
        alignment: alignment,
        cacheManager: ImageCacheManager.i.cacheManager,
        httpHeaders: headers,
        fadeInDuration: fade ? Motion.fast : Duration.zero,
        fadeOutDuration: fade ? Motion.fast : Duration.zero,
        memCacheWidth: memW,
        memCacheHeight: memH,
        placeholder: (ctx, _) => placeholder(ctx, trimmed),
        errorWidget: errorWidget,
      );
    }

    if (radius != null) {
      child = ClipRRect(
        borderRadius: radius!,
        child: child,
      );
    }

    return child;
  }
}

const kImageUa =
    'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Mobile Safari/537.36';

/// Same cache and Referer rules as [PzImage], for widgets that need a raw provider.
ImageProvider pzImageProvider(String url, {String? referer}) => CachedNetworkImageProvider(
      url,
      cacheManager: ImageCacheManager.i.cacheManager,
      headers: referer == null || referer.isEmpty ? null : {'Referer': referer, 'User-Agent': kImageUa},
    );

/// The right provider for a reader page: a downloaded file, an extension page
/// (fetched natively through the extension), or a plain cached URL.
ImageProvider pageImageProvider(MPage p) {
  if (p.isFile) return FileImage(File(p.url.substring(7)));
  if (p.ext != null) return ExtPageImage(p);
  return pzImageProvider(p.url, referer: p.referer);
}

/// A page from a Mihon extension. The native host downloads it with the
/// source's own client and hands back a cached file.
@immutable
class ExtPageImage extends ImageProvider<ExtPageImage> {
  const ExtPageImage(this.page);

  final MPage page;

  @override
  Future<ExtPageImage> obtainKey(ImageConfiguration configuration) => SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(ExtPageImage key, ImageDecoderCallback decode) =>
      MultiFrameImageStreamCompleter(codec: _load(decode), scale: 1);

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    final path = await Extensions.i.image(page);
    final bytes = await File(path).readAsBytes();
    return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }

  @override
  bool operator ==(Object other) =>
      other is ExtPageImage && other.page.ext == page.ext && other.page.pageUrl == page.pageUrl && other.page.imageUrl == page.imageUrl && other.page.index == page.index;

  @override
  int get hashCode => Object.hash(page.ext, page.pageUrl, page.imageUrl, page.index);
}
