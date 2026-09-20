import 'dart:io';

enum FileItemType {
  folder,
  file,
  image,
  video,
  audio,
  document,
  archive,
  apk,
}

class FileItem {
  final String path;
  final String name;
  final FileItemType type;
  final int sizeBytes;
  final String size;
  final DateTime modifiedTime;
  final String dateModified;
  final bool isDirectory;

  const FileItem({
    required this.path,
    required this.name,
    required this.type,
    required this.sizeBytes,
    required this.size,
    required this.modifiedTime,
    required this.dateModified,
    this.isDirectory = false,
  });

  factory FileItem.fromFileSystemEntity(FileSystemEntity entity, {FileStat? stat}) {
    final entityStat = stat ?? entity.statSync();
    final isDir = entity is Directory || entityStat.type == FileSystemEntityType.directory;
    final name = entity.uri.pathSegments.where((s) => s.isNotEmpty).isEmpty
        ? entity.path
        : entity.uri.pathSegments.where((s) => s.isNotEmpty).last;

    final type = isDir ? FileItemType.folder : _determineFileType(name);
    final sizeBytes = isDir ? 0 : entityStat.size;
    final sizeFormatted = isDir ? '--' : _formatFileSize(sizeBytes);
    final modified = entityStat.modified;
    final dateFormatted = _formatDateTime(modified);

    return FileItem(
      path: entity.path,
      name: name,
      type: type,
      sizeBytes: sizeBytes,
      size: sizeFormatted,
      modifiedTime: modified,
      dateModified: dateFormatted,
      isDirectory: isDir,
    );
  }

  static FileItemType _determineFileType(String fileName) {
    final ext = fileName.contains('.') ? fileName.split('.').last.toLowerCase() : '';
    switch (ext) {
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'webp':
      case 'bmp':
      case 'svg':
        return FileItemType.image;
      case 'mp4':
      case 'mkv':
      case 'avi':
      case 'mov':
      case 'webm':
      case '3gp':
        return FileItemType.video;
      case 'mp3':
      case 'wav':
      case 'flac':
      case 'aac':
      case 'ogg':
      case 'm4a':
        return FileItemType.audio;
      case 'pdf':
      case 'doc':
      case 'docx':
      case 'txt':
      case 'rtf':
      case 'xls':
      case 'xlsx':
      case 'ppt':
      case 'pptx':
      case 'csv':
      case 'md':
        return FileItemType.document;
      case 'zip':
      case 'rar':
      case '7z':
      case 'tar':
      case 'gz':
      case 'bz2':
      case 'xz':
        return FileItemType.archive;
      case 'apk':
      case 'apks':
      case 'xapk':
        return FileItemType.apk;
      default:
        return FileItemType.file;
    }
  }

  static String _formatFileSize(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  static String _formatDateTime(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }
}
