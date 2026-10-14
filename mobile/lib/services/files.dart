/// The file-system seam.
///
/// `dart:io` does not exist on the web, and importing it anywhere in the tree
/// breaks the web build outright. Everything that touches a real file goes
/// through this facade, which resolves to the `dart:io` implementation on
/// Android and to a harmless stub in a browser tab.
///
/// Nothing outside `files_io.dart` and `files_web.dart` may import `dart:io`.
library;

export 'files_io.dart' if (dart.library.js_interop) 'files_web.dart';
