import 'dart:io';

/// Configuration for a file type supported by MOD plugins
class FileTypeConfig {
  final String id;
  final String label;
  final String directory;
  final List<String> extensions;

  const FileTypeConfig({
    required this.id,
    required this.label,
    required this.directory,
    required this.extensions,
  });

  /// Get the full path to the directory for this file type
  String getDirectoryPath() {
    final basePath = Platform.environment['MOD_USER_FILES_DIR'] ?? '/data/user-files';
    return '$basePath/$directory';
  }

  /// Check if a file matches this file type
  bool matchesFile(String path) {
    final lowerPath = path.toLowerCase();
    return extensions.any((ext) => lowerPath.endsWith(ext));
  }
}

/// Registry of all supported file types
class FileTypes {
  static const audiosample = FileTypeConfig(
    id: 'audiosample',
    label: 'Audio Samples',
    directory: 'Audio Samples',
    extensions: ['.wav', '.flac', '.ogg', '.mp3', '.aiff', '.aif'],
  );

  static const cabsim = FileTypeConfig(
    id: 'cabsim',
    label: 'Speaker Cabinets IRs',
    directory: 'Speaker Cabinets IRs',
    extensions: ['.wav', '.flac'],
  );

  static const ir = FileTypeConfig(
    id: 'ir',
    label: 'Reverb IRs',
    directory: 'Reverb IRs',
    extensions: ['.wav', '.flac'],
  );

  static const sf2 = FileTypeConfig(
    id: 'sf2',
    label: 'SF2 Instruments',
    directory: 'SF2 Instruments',
    extensions: ['.sf2', '.sf3'],
  );

  static const sfz = FileTypeConfig(
    id: 'sfz',
    label: 'SFZ Instruments',
    directory: 'SFZ Instruments',
    extensions: ['.sfz'],
  );

  static const aidadspmodel = FileTypeConfig(
    id: 'aidadspmodel',
    label: 'Aida DSP Models',
    directory: 'Aida DSP Models',
    extensions: ['.aidax', '.json'],
  );

  static const nammodel = FileTypeConfig(
    id: 'nammodel',
    label: 'NAM Models',
    directory: 'NAM Models',
    extensions: ['.nam'],
  );

  static const midifile = FileTypeConfig(
    id: 'midifile',
    label: 'MIDI Files',
    directory: 'MIDI Files',
    extensions: ['.mid', '.midi'],
  );

  /// Get all registered file types
  static const List<FileTypeConfig> all = [
    audiosample,
    cabsim,
    ir,
    sf2,
    sfz,
    aidadspmodel,
    nammodel,
    midifile,
  ];

  /// Get file type config by ID
  static FileTypeConfig? getById(String id) {
    final lowerId = id.toLowerCase();
    for (final config in all) {
      if (config.id == lowerId) {
        return config;
      }
    }
    return null;
  }

  /// Get file type config by any of several IDs (for plugins that support multiple types)
  static List<FileTypeConfig> getByIds(List<String> ids) {
    final configs = <FileTypeConfig>[];
    for (final id in ids) {
      final config = getById(id);
      if (config != null && !configs.contains(config)) {
        configs.add(config);
      }
    }
    return configs;
  }

  /// List all files for the given file types
  static Future<List<FileInfo>> listFiles(List<String> fileTypes) async {
    final files = <FileInfo>[];
    final configs = getByIds(fileTypes);

    for (final config in configs) {
      final dirPath = config.getDirectoryPath();
      final dir = Directory(dirPath);

      if (await dir.exists()) {
        await for (final entity in dir.list(recursive: true)) {
          if (entity is File && config.matchesFile(entity.path)) {
            files.add(FileInfo(
              path: entity.path,
              name: entity.path.split('/').last,
              fileType: config,
            ));
          }
        }
      }
    }

    // Sort by name
    files.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return files;
  }
}

/// Information about a file that can be loaded by a plugin
class FileInfo {
  final String path;
  final String name;
  final FileTypeConfig fileType;

  FileInfo({
    required this.path,
    required this.name,
    required this.fileType,
  });

  @override
  String toString() => 'FileInfo($name)';
}
