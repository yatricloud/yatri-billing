import 'dart:io' show File;
import 'dart:typed_data' show Uint8List;

import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';

/// Cross-platform file saving.
///
/// On web it triggers a browser download (via `file_saver`) and returns the
/// original [filename]. On desktop it writes [bytes] to [directory] (or the
/// user's Documents folder when [directory] is null) and returns the full
/// path — this preserves the original desktop behavior exactly.
class SaveFile {
  static Future<String> save({
    required String filename,
    required List<int> bytes,
    String? directory,
    String extension = '',
  }) async {
    if (kIsWeb) {
      final ext = extension.isEmpty ? _extOf(filename) : extension;
      await FileSaver.instance.saveFile(
        name: _baseOf(filename),
        bytes: bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
        fileExtension: ext,
        mimeType: _mimeOf(ext),
      );
      return filename;
    }
    final dir = directory ?? (await getApplicationDocumentsDirectory()).path;
    final file = File('$dir/$filename');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  /// Strips the trailing extension so `file_saver` re-appends it correctly
  /// (the web download name is `name + fileExtension`).
  static String _baseOf(String f) {
    final i = f.lastIndexOf('.');
    return i > 0 ? f.substring(0, i) : f;
  }

  static String _extOf(String f) => f.contains('.') ? f.split('.').last : 'txt';

  static MimeType _mimeOf(String ext) {
    switch (ext.toLowerCase()) {
      case 'pdf':
        return MimeType.pdf;
      case 'csv':
        return MimeType.csv;
      case 'zip':
        return MimeType.zip;
      default:
        return MimeType.other;
    }
  }

  /// Reads bytes from a [FilePicker] result on web (`bytes`) or desktop (`path`).
  static Future<Uint8List?> readPickedFile(PlatformFile file) async {
    if (file.bytes != null) return file.bytes;
    final path = file.path;
    if (path == null) return null;
    return File(path).readAsBytes();
  }

  /// Saves [bytes] to disk. On web triggers a browser download; on desktop
  /// opens a save dialog first (returns null if the user cancels).
  static Future<String?> saveWithDialog({
    required String filename,
    required List<int> bytes,
    String dialogTitle = 'Save File',
    String extension = '',
  }) async {
    if (kIsWeb) {
      return save(
        filename: filename,
        bytes: bytes,
        extension: extension.isEmpty ? _extOf(filename) : extension,
      );
    }
    final ext = extension.isEmpty ? _extOf(filename) : extension;
    final savePath = await FilePicker.platform.saveFile(
      dialogTitle: dialogTitle,
      fileName: filename,
      type: FileType.custom,
      allowedExtensions: [ext],
    );
    if (savePath == null) return null;
    await File(savePath).writeAsBytes(bytes);
    return savePath;
  }
}
