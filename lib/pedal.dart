import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:logging/logging.dart';
import 'package:rdflib/rdflib.dart';

final _log = Logger('Pedal');

/// Represents a scale point (enumeration value) on a control port
class ScalePoint {
  final String label;
  final double value;

  ScalePoint({required this.label, required this.value});

  Map<String, dynamic> toJson() => {
    'label': label,
    'value': value,
  };

  factory ScalePoint.fromJson(Map<String, dynamic> json) => ScalePoint(
    label: json['label'],
    value: (json['value'] as num).toDouble(),
  );
}

/// Represents a file parameter (atom:Path) on a plugin
class FileParameter {
  final String uri;
  final String label;
  final List<String> fileTypes;
  String? currentPath;

  FileParameter({
    required this.uri,
    required this.label,
    required this.fileTypes,
    this.currentPath,
  });

  Map<String, dynamic> toJson() => {
    'uri': uri,
    'label': label,
    'fileTypes': fileTypes,
    'currentPath': currentPath,
  };

  factory FileParameter.fromJson(Map<String, dynamic> json) => FileParameter(
    uri: json['uri'],
    label: json['label'],
    fileTypes: List<String>.from(json['fileTypes'] ?? []),
    currentPath: json['currentPath'],
  );

  @override
  String toString() => 'FileParameter($label: $currentPath)';
}

/// Represents a control port (parameter) on a plugin
class ControlPort {
  final String symbol;
  final String name;
  final double minimum;
  final double maximum;
  final double defaultValue;
  final bool isToggled;
  final bool isInteger;
  final bool isTrigger;
  final bool isOutput;
  final bool isEnumeration;
  final List<ScalePoint> scalePoints;
  double currentValue;

  ControlPort({
    required this.symbol,
    required this.name,
    required this.minimum,
    required this.maximum,
    required this.defaultValue,
    this.isToggled = false,
    this.isInteger = false,
    this.isTrigger = false,
    this.isOutput = false,
    this.isEnumeration = false,
    List<ScalePoint>? scalePoints,
    double? currentValue,
  }) : scalePoints = scalePoints ?? [],
       currentValue = currentValue ?? defaultValue;

  Map<String, dynamic> toJson() => {
    'symbol': symbol,
    'name': name,
    'minimum': minimum,
    'maximum': maximum,
    'defaultValue': defaultValue,
    'isToggled': isToggled,
    'isInteger': isInteger,
    'isTrigger': isTrigger,
    'isOutput': isOutput,
    'isEnumeration': isEnumeration,
    'scalePoints': scalePoints.map((sp) => sp.toJson()).toList(),
  };

  factory ControlPort.fromJson(Map<String, dynamic> json) => ControlPort(
    symbol: json['symbol'],
    name: json['name'],
    minimum: (json['minimum'] as num).toDouble(),
    maximum: (json['maximum'] as num).toDouble(),
    defaultValue: (json['defaultValue'] as num).toDouble(),
    isToggled: json['isToggled'] ?? false,
    isInteger: json['isInteger'] ?? false,
    isTrigger: json['isTrigger'] ?? false,
    isOutput: json['isOutput'] ?? false,
    isEnumeration: json['isEnumeration'] ?? false,
    scalePoints: (json['scalePoints'] as List?)
        ?.map((sp) => ScalePoint.fromJson(sp))
        .toList(),
  );

  @override
  String toString() => 'ControlPort($symbol: $currentValue [$minimum-$maximum])';
}

/// Represents an LV2 plugin instance within a pedalboard
class Pedal {
  final String instanceName;
  final String pluginUri;
  final int instanceNumber;
  final bool enabled;
  final Map<String, double> portValues;
  final Map<String, String> fileValues;

  // Plugin metadata (loaded from LV2 bundle)
  String? label;
  String? brand;
  String? thumbnailPath;
  List<ControlPort>? controlPorts;
  List<FileParameter>? fileParameters;

  Pedal({
    required this.instanceName,
    required this.pluginUri,
    required this.instanceNumber,
    required this.enabled,
    Map<String, double>? portValues,
    Map<String, String>? fileValues,
  }) : portValues = portValues ?? {},
       fileValues = fileValues ?? {};

  /// Load plugin metadata from its LV2 bundle
  Future<void> loadMetadata(LV2PluginCache cache) async {
    final info = await cache.getPluginInfo(pluginUri);
    if (info != null) {
      label = info.label;
      brand = info.brand;
      thumbnailPath = info.thumbnailPath;

      // Load control ports and apply current values
      controlPorts = info.controlPorts.map((port) {
        final currentVal = portValues[port.symbol];
        return ControlPort(
          symbol: port.symbol,
          name: port.name,
          minimum: port.minimum,
          maximum: port.maximum,
          defaultValue: port.defaultValue,
          isToggled: port.isToggled,
          isInteger: port.isInteger,
          isTrigger: port.isTrigger,
          isOutput: port.isOutput,
          isEnumeration: port.isEnumeration,
          scalePoints: port.scalePoints,
          currentValue: currentVal,
        );
      }).toList();

      // Load file parameters and apply current values
      fileParameters = info.fileParameters.map((param) {
        final currentPath = fileValues[param.uri];
        return FileParameter(
          uri: param.uri,
          label: param.label,
          fileTypes: param.fileTypes,
          currentPath: currentPath,
        );
      }).toList();
    }
  }

  @override
  String toString() => 'Pedal($instanceName: $pluginUri)';
}

/// Information about an LV2 plugin from its modgui.ttl and main TTL
class LV2PluginInfo {
  final String uri;
  final String bundlePath;
  final String? label;
  final String? brand;
  final String? thumbnailPath;
  final List<ControlPort> controlPorts;
  final List<FileParameter> fileParameters;

  LV2PluginInfo({
    required this.uri,
    required this.bundlePath,
    this.label,
    this.brand,
    this.thumbnailPath,
    List<ControlPort>? controlPorts,
    List<FileParameter>? fileParameters,
  }) : controlPorts = controlPorts ?? [],
       fileParameters = fileParameters ?? [];

  Map<String, dynamic> toJson() => {
    'uri': uri,
    'bundlePath': bundlePath,
    'label': label,
    'brand': brand,
    'thumbnailPath': thumbnailPath,
    'controlPorts': controlPorts.map((p) => p.toJson()).toList(),
    'fileParameters': fileParameters.map((p) => p.toJson()).toList(),
  };

  factory LV2PluginInfo.fromJson(Map<String, dynamic> json) => LV2PluginInfo(
    uri: json['uri'],
    bundlePath: json['bundlePath'],
    label: json['label'],
    brand: json['brand'],
    thumbnailPath: json['thumbnailPath'],
    controlPorts: (json['controlPorts'] as List?)
        ?.map((p) => ControlPort.fromJson(p))
        .toList(),
    fileParameters: (json['fileParameters'] as List?)
        ?.map((p) => FileParameter.fromJson(p))
        .toList(),
  );
}

/// Cache for LV2 plugin information
/// Uses on-demand loading with disk caching for fast startup
class LV2PluginCache {
  static LV2PluginCache? _instance;

  // URI -> bundle path index (built once on first use)
  final Map<String, String> _uriIndex = {};

  // Loaded plugin info cache
  final Map<String, LV2PluginInfo> _cache = {};

  bool _indexBuilt = false;
  String? _cacheFilePath;

  LV2PluginCache._();

  static LV2PluginCache get instance {
    _instance ??= LV2PluginCache._();
    return _instance!;
  }

  String get _defaultCachePath {
    final home = Platform.environment['HOME'] ?? '/tmp';
    return '$home/.cache/pi-ede-ui/lv2_cache.json';
  }

  /// Get plugin info by URI (loads on-demand)
  Future<LV2PluginInfo?> getPluginInfo(String uri) async {
    // Check memory cache first
    if (_cache.containsKey(uri)) {
      return _cache[uri];
    }

    // Build index if not done yet
    if (!_indexBuilt) {
      await _buildIndex();
    }

    // Check if we know where this plugin is
    final bundlePath = _uriIndex[uri];
    if (bundlePath == null) {
      _log.warning('Unknown plugin URI: $uri');
      return null;
    }

    // Load plugin info in isolate
    final info = await Isolate.run(() => _loadPluginSync(uri, bundlePath));
    if (info != null) {
      _cache[uri] = info;
      // Save to disk cache in background
      _saveCacheAsync();
    }

    return info;
  }

  /// Build URI -> bundle path index (fast, only reads manifest.ttl)
  Future<void> _buildIndex() async {
    if (_indexBuilt) return;

    // Try to load from disk cache first
    await _loadDiskCache();

    final lv2Paths = <String>[
      '/usr/lib/lv2',
      '/usr/local/lib/lv2',
      '${Platform.environment['HOME']}/.lv2',
    ];

    // Build index in isolate
    final index = await Isolate.run(() => _buildIndexInIsolate(lv2Paths));
    _uriIndex.addAll(index);

    _indexBuilt = true;
    _log.info('LV2 plugin index built with ${_uriIndex.length} plugins');
  }

  /// Load disk cache
  Future<void> _loadDiskCache() async {
    try {
      final cacheFile = File(_defaultCachePath);
      if (await cacheFile.exists()) {
        final content = await cacheFile.readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;
        final plugins = json['plugins'] as Map<String, dynamic>?;
        if (plugins != null) {
          for (final entry in plugins.entries) {
            _cache[entry.key] = LV2PluginInfo.fromJson(entry.value);
            _uriIndex[entry.key] = _cache[entry.key]!.bundlePath;
          }
          _log.info('Loaded ${_cache.length} plugins from disk cache');
        }
      }
    } catch (e) {
      _log.warning('Failed to load disk cache: $e');
    }
  }

  /// Save cache to disk (async, non-blocking)
  void _saveCacheAsync() {
    Future(() async {
      try {
        final cacheFile = File(_defaultCachePath);
        await cacheFile.parent.create(recursive: true);

        final json = {
          'version': 1,
          'plugins': _cache.map((k, v) => MapEntry(k, v.toJson())),
        };

        await cacheFile.writeAsString(jsonEncode(json));
      } catch (e) {
        _log.warning('Failed to save disk cache: $e');
      }
    });
  }

  /// Clear the cache and rebuild
  Future<void> refresh() async {
    _cache.clear();
    _uriIndex.clear();
    _indexBuilt = false;

    // Delete disk cache
    try {
      final cacheFile = File(_defaultCachePath);
      if (await cacheFile.exists()) {
        await cacheFile.delete();
      }
    } catch (e) {
      _log.warning('Failed to delete cache file: $e');
    }

    _log.info('LV2 plugin cache cleared');
  }

  /// Build URI index in isolate (only parses manifest.ttl for speed)
  static Map<String, String> _buildIndexInIsolate(List<String> lv2Paths) {
    final index = <String, String>{};

    for (final lv2Path in lv2Paths) {
      final dir = Directory(lv2Path);
      if (!dir.existsSync()) continue;

      for (final bundle in dir.listSync()) {
        if (bundle is Directory && bundle.path.endsWith('.lv2')) {
          final manifestFile = File('${bundle.path}/manifest.ttl');
          if (!manifestFile.existsSync()) continue;

          try {
            final g = Graph();
            g.parseTurtle(manifestFile.readAsStringSync());

            // Find all plugins in this bundle
            final pluginTriples = g.triples.where((t) =>
                t.pre.value == 'http://www.w3.org/1999/02/22-rdf-syntax-ns#type' &&
                t.obj.value == 'http://lv2plug.in/ns/lv2core#Plugin');

            for (final triple in pluginTriples) {
              index[triple.sub.value] = bundle.path;
            }
          } catch (e) {
            // Skip problematic bundles
          }
        }
      }
    }

    return index;
  }

  /// Load a single plugin's full info (for use in isolate)
  static LV2PluginInfo? _loadPluginSync(String uri, String bundlePath) {
    String? label;
    String? brand;
    String? thumbnailPath;

    // First try to get label/brand/thumbnail from modgui.ttl or modguis.ttl
    final modguiFile = File('$bundlePath/modgui.ttl');
    final modguisFile = File('$bundlePath/modguis.ttl');

    if (modguiFile.existsSync()) {
      final content = modguiFile.readAsStringSync();
      _extractModguiData(content, bundlePath, (l, b, t) {
        label = l;
        brand = b;
        thumbnailPath = t;
      }, uri: uri);
    }

    // Check modguis.ttl (plural) for multi-plugin bundles like rkr.lv2
    if ((label == null || thumbnailPath == null) && modguisFile.existsSync()) {
      final content = modguisFile.readAsStringSync();
      _extractModguiData(content, bundlePath, (l, b, t) {
        label ??= l;
        brand ??= b;
        thumbnailPath ??= t;
      }, uri: uri);
    }

    // If missing data, also check main plugin TTL files (some plugins embed modgui there)
    if (label == null || thumbnailPath == null) {
      final ttlFiles = _getPluginTtlFiles(uri, bundlePath);
      for (final ttlFile in ttlFiles) {
        if (ttlFile.existsSync()) {
          final content = ttlFile.readAsStringSync();
          _extractModguiData(content, bundlePath, (l, b, t) {
            label ??= l;
            brand ??= b;
            thumbnailPath ??= t;
          }, uri: uri);
          if (label != null && thumbnailPath != null) break;
        }
      }
    }

    // If no label from modgui, try doap:name from the main plugin TTL
    if (label == null) {
      label = _getDoapNameFromPluginTtl(uri, bundlePath);
    }

    // Final fallback: extract from URI
    label ??= uri.split('/').last.split('#').last;

    // Load control ports
    final controlPorts = _loadControlPortsSync(uri, bundlePath);

    // Load file parameters
    final fileParameters = _loadFileParametersSync(uri, bundlePath);

    return LV2PluginInfo(
      uri: uri,
      bundlePath: bundlePath,
      label: label,
      brand: brand,
      thumbnailPath: thumbnailPath,
      controlPorts: controlPorts,
      fileParameters: fileParameters,
    );
  }

  /// Extract modgui data (label, brand, thumbnail) from TTL content using regex
  /// If uri is provided, only extract data for that specific plugin URI
  static void _extractModguiData(
    String content,
    String bundlePath,
    void Function(String? label, String? brand, String? thumbnailPath) onData,
    {String? uri}
  ) {
    String? label;
    String? brand;
    String? thumbnailPath;

    String searchContent = content;

    // If a specific URI is provided and the file contains multiple plugins,
    // try to extract only the block for that URI
    if (uri != null && content.contains(uri)) {
      // Find the block starting with <uri> and ending with ] .
      // The pattern matches: <uri> modgui:gui [ ... ] .
      final escapedUri = RegExp.escape(uri);
      final blockMatch = RegExp(
        '<$escapedUri>\\s*modgui:gui\\s*\\[([^\\]]*(?:\\[[^\\]]*\\][^\\]]*)*)\\]',
        multiLine: true,
        dotAll: true,
      ).firstMatch(content);

      if (blockMatch != null) {
        searchContent = blockMatch.group(0) ?? content;
      }
    }

    // Extract label: modgui:label "value"
    final labelMatch = RegExp(r'modgui:label\s+"([^"]+)"').firstMatch(searchContent);
    if (labelMatch != null) {
      label = labelMatch.group(1);
    }

    // Extract brand: modgui:brand "value"
    final brandMatch = RegExp(r'modgui:brand\s+"([^"]+)"').firstMatch(searchContent);
    if (brandMatch != null) {
      brand = brandMatch.group(1);
    }

    // Extract thumbnail: modgui:thumbnail <path>
    final thumbMatch = RegExp(r'modgui:thumbnail\s+<([^>]+)>').firstMatch(searchContent);
    if (thumbMatch != null) {
      thumbnailPath = '$bundlePath/${thumbMatch.group(1)}';
    }

    onData(label, brand, thumbnailPath);
  }

  /// Get list of plugin TTL files from manifest (excluding modgui.ttl)
  static List<File> _getPluginTtlFiles(String uri, String bundlePath) {
    final files = <File>[];
    final manifestFile = File('$bundlePath/manifest.ttl');
    if (!manifestFile.existsSync()) return files;

    try {
      final manifestGraph = Graph();
      manifestGraph.parseTurtle(manifestFile.readAsStringSync());

      // Find rdfs:seeAlso references for this plugin
      final seeAlsoTriples = manifestGraph.triples.where((t) =>
          t.sub.value == uri &&
          t.pre.value == 'http://www.w3.org/2000/01/rdf-schema#seeAlso');

      for (final seeAlso in seeAlsoTriples) {
        final ref = seeAlso.obj;
        if (ref is URIRef && !ref.value.contains('modgui')) {
          files.add(File('$bundlePath/${ref.value}'));
        }
      }
    } catch (e) {
      // Skip problematic manifest files
    }

    return files;
  }

  /// Get doap:name from the main plugin TTL file
  static String? _getDoapNameFromPluginTtl(String uri, String bundlePath) {
    final manifestFile = File('$bundlePath/manifest.ttl');
    if (!manifestFile.existsSync()) return null;

    try {
      final manifestGraph = Graph();
      manifestGraph.parseTurtle(manifestFile.readAsStringSync());

      // Find rdfs:seeAlso references for this plugin (excluding modgui.ttl)
      final seeAlsoTriples = manifestGraph.triples.where((t) =>
          t.sub.value == uri &&
          t.pre.value == 'http://www.w3.org/2000/01/rdf-schema#seeAlso');

      for (final seeAlso in seeAlsoTriples) {
        final ref = seeAlso.obj;
        if (ref is URIRef && !ref.value.contains('modgui')) {
          final ttlPath = '$bundlePath/${ref.value}';
          final ttlFile = File(ttlPath);
          if (ttlFile.existsSync()) {
            try {
              final g = Graph();
              g.parseTurtle(ttlFile.readAsStringSync());

              // Find doap:name for this plugin URI
              final nameTriples = g.triples.where((t) =>
                  t.sub.value == uri &&
                  t.pre.value == 'http://usefulinc.com/ns/doap#name');

              if (nameTriples.isNotEmpty) {
                final nameObj = nameTriples.first.obj;
                if (nameObj is Literal) {
                  return nameObj.value;
                }
              }
            } catch (e) {
              // Skip problematic TTL files
            }
          }
        }
      }
    } catch (e) {
      // Skip problematic manifest files
    }

    return null;
  }

  /// Load control ports synchronously using regex (rdflib can't handle port lists)
  static List<ControlPort> _loadControlPortsSync(String uri, String bundlePath) {
    final ports = <ControlPort>[];

    // Get plugin TTL files
    final ttlFiles = _getPluginTtlFiles(uri, bundlePath);
    for (final ttlFile in ttlFiles) {
      if (ttlFile.existsSync()) {
        _parseControlPortsWithRegex(ttlFile.readAsStringSync(), ports);
        if (ports.isNotEmpty) break;
      }
    }

    return ports;
  }

  /// Parse control ports from TTL content using regex
  static void _parseControlPortsWithRegex(String content, List<ControlPort> ports) {
    // Find port block starts: [ a ...lv2:ControlPort
    final portStartRegex = RegExp(
      r'\[\s*a\s+[^;]*lv2:ControlPort',
      multiLine: true,
    );

    // For each port start, find the matching closing bracket
    final portBlocks = <String>[];
    for (final match in portStartRegex.allMatches(content)) {
      final start = match.start;
      var depth = 0;
      var end = start;
      for (var i = start; i < content.length; i++) {
        if (content[i] == '[') {
          depth++;
        } else if (content[i] == ']') {
          depth--;
          if (depth == 0) {
            end = i + 1;
            break;
          }
        }
      }
      if (end > start) {
        portBlocks.add(content.substring(start, end));
      }
    }

    // Regex for numbers including scientific notation (e.g., 3.6e+02, 1e-05)
    final numRegex = r'([+-]?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?)';

    for (final block in portBlocks) {

      // Check if it's an output port
      final isOutput = block.contains('lv2:OutputPort');

      // Extract symbol
      final symbolMatch = RegExp(r'lv2:symbol\s+"([^"]+)"').firstMatch(block);
      if (symbolMatch == null) continue;
      final symbol = symbolMatch.group(1)!;

      // Extract name
      final nameMatch = RegExp(r'lv2:name\s+"([^"]+)"').firstMatch(block);
      final name = nameMatch?.group(1) ?? symbol;

      // Extract minimum (handles scientific notation)
      final minMatch = RegExp('lv2:minimum\\s+$numRegex').firstMatch(block);
      final minimum = double.tryParse(minMatch?.group(1) ?? '0') ?? 0;

      // Extract maximum (handles scientific notation)
      final maxMatch = RegExp('lv2:maximum\\s+$numRegex').firstMatch(block);
      final maximum = double.tryParse(maxMatch?.group(1) ?? '1') ?? 1;

      // Extract default (handles scientific notation)
      final defMatch = RegExp('lv2:default\\s+$numRegex').firstMatch(block);
      final defaultValue = double.tryParse(defMatch?.group(1) ?? '0') ?? 0;

      // Check port properties
      final isToggled = block.contains('lv2:toggled');
      final isInteger = block.contains('lv2:integer');
      final isTrigger = block.contains('epp:trigger') || block.contains('port-props#trigger');
      final isEnumeration = block.contains('lv2:enumeration');

      // Parse scale points for enumeration ports
      final scalePoints = <ScalePoint>[];
      if (isEnumeration) {
        // Match scale point blocks in either order:
        // [ rdfs:label "Label" ; rdf:value 0 ; ] or [ rdf:value 0 ; rdfs:label "Label" ; ]
        // The trailing ; before ] is optional
        final scalePointRegex1 = RegExp(
          r'\[\s*rdfs:label\s+"([^"]+)"\s*;\s*rdf:value\s+' + numRegex + r'\s*;?\s*\]',
          multiLine: true,
        );
        final scalePointRegex2 = RegExp(
          r'\[\s*rdf:value\s+' + numRegex + r'\s*;\s*rdfs:label\s+"([^"]+)"\s*;?\s*\]',
          multiLine: true,
        );

        for (final spMatch in scalePointRegex1.allMatches(block)) {
          final label = spMatch.group(1);
          final value = double.tryParse(spMatch.group(2) ?? '0') ?? 0;
          if (label != null) {
            scalePoints.add(ScalePoint(label: label, value: value));
          }
        }
        for (final spMatch in scalePointRegex2.allMatches(block)) {
          final value = double.tryParse(spMatch.group(1) ?? '0') ?? 0;
          final label = spMatch.group(2);
          if (label != null) {
            scalePoints.add(ScalePoint(label: label, value: value));
          }
        }
        // Sort by value
        scalePoints.sort((a, b) => a.value.compareTo(b.value));
      }

      ports.add(ControlPort(
        symbol: symbol,
        name: name,
        minimum: minimum,
        maximum: maximum,
        defaultValue: defaultValue,
        isToggled: isToggled,
        isInteger: isInteger,
        isTrigger: isTrigger,
        isOutput: isOutput,
        isEnumeration: isEnumeration,
        scalePoints: scalePoints,
      ));
    }
  }

  /// Load file parameters (atom:Path parameters) using regex
  static List<FileParameter> _loadFileParametersSync(String uri, String bundlePath) {
    final params = <FileParameter>[];

    // Get plugin TTL files
    final ttlFiles = _getPluginTtlFiles(uri, bundlePath);
    for (final ttlFile in ttlFiles) {
      if (ttlFile.existsSync()) {
        _parseFileParametersWithRegex(ttlFile.readAsStringSync(), params);
        if (params.isNotEmpty) break;
      }
    }

    return params;
  }

  /// Parse file parameters from TTL content using regex
  /// File parameters are declared as patch:writable with rdfs:range atom:Path
  static void _parseFileParametersWithRegex(String content, List<FileParameter> params) {
    // Build prefix map from @prefix declarations
    final prefixMap = <String, String>{};
    final prefixRegex = RegExp(r'@prefix\s+(\w+):\s+<([^>]+)>\s*\.', multiLine: true);
    for (final match in prefixRegex.allMatches(content)) {
      final prefix = match.group(1);
      final uri = match.group(2);
      if (prefix != null && uri != null) {
        prefixMap[prefix] = uri;
      }
    }

    // Collect all parameter references declared as writable
    // Matches both: patch:writable <full_uri> and patch:writable prefix:name
    final writableRefs = <String>{};

    // Match full URIs: patch:writable <uri>
    final writableUriRegex = RegExp(r'patch:writable\s+<([^>]+)>', multiLine: true);
    for (final match in writableUriRegex.allMatches(content)) {
      final uri = match.group(1);
      if (uri != null) writableRefs.add('<$uri>');
    }

    // Match prefixed names: patch:writable prefix:name
    final writablePrefixRegex = RegExp(r'patch:writable\s+(\w+:\w+)', multiLine: true);
    for (final match in writablePrefixRegex.allMatches(content)) {
      final prefixedName = match.group(1);
      if (prefixedName != null) writableRefs.add(prefixedName);
    }

    if (writableRefs.isEmpty) return;

    // Find all lv2:Parameter definitions with atom:Path range
    // Match both full URI and prefixed forms
    // Pattern: <uri> or prefix:name  a lv2:Parameter ; ... rdfs:range atom:Path
    final paramDefRegex = RegExp(
      r'((?:<[^>]+>)|(?:\w+:\w+))\s+a\s+lv2:Parameter\s*;([^.]*(?:\[[^\]]*\][^.]*)*)\.',
      multiLine: true,
      dotAll: true,
    );

    for (final match in paramDefRegex.allMatches(content)) {
      final paramRef = match.group(1)?.trim();
      final block = match.group(0) ?? '';

      if (paramRef == null) continue;

      // Check if this parameter is in the writable list
      if (!writableRefs.contains(paramRef)) continue;

      // Check if this is an atom:Path parameter
      if (!block.contains('atom:Path')) continue;

      // Resolve the full URI
      String paramUri;
      if (paramRef.startsWith('<') && paramRef.endsWith('>')) {
        paramUri = paramRef.substring(1, paramRef.length - 1);
      } else if (paramRef.contains(':')) {
        final parts = paramRef.split(':');
        final prefix = parts[0];
        final localName = parts[1];
        final baseUri = prefixMap[prefix];
        if (baseUri != null) {
          paramUri = '$baseUri$localName';
        } else {
          paramUri = paramRef;
        }
      } else {
        paramUri = paramRef;
      }

      // Extract label
      final labelMatch = RegExp(r'rdfs:label\s+"([^"]+)"').firstMatch(block);
      final label = labelMatch?.group(1) ?? paramUri.split('#').last.split('/').last;

      // Extract file types from mod:fileTypes
      final fileTypes = <String>[];

      final fileTypesMatch = RegExp(
        r'mod:fileTypes\s+([^;]+)',
        multiLine: true,
      ).firstMatch(block);

      if (fileTypesMatch != null) {
        final typesStr = fileTypesMatch.group(1)!.trim();

        // Check if it's a quoted string (e.g., "nammodel,aidadspmodel,nam")
        final quotedMatch = RegExp(r'"([^"]+)"').firstMatch(typesStr);
        if (quotedMatch != null) {
          // Parse comma-separated string
          final types = quotedMatch.group(1)!.split(',');
          for (final type in types) {
            final normalizedType = _normalizeFileType(type.trim());
            if (normalizedType != null && !fileTypes.contains(normalizedType)) {
              fileTypes.add(normalizedType);
            }
          }
        } else {
          // Try mod:TypeName format
          final typeMatches = RegExp(r'mod:(\w+)').allMatches(typesStr);
          for (final typeMatch in typeMatches) {
            final typeId = typeMatch.group(1);
            if (typeId != null) {
              final fileType = _modTypeToFileType(typeId);
              if (fileType != null && !fileTypes.contains(fileType)) {
                fileTypes.add(fileType);
              }
            }
          }
        }
      }

      if (fileTypes.isEmpty) {
        fileTypes.add('file');
      }

      params.add(FileParameter(
        uri: paramUri,
        label: label,
        fileTypes: fileTypes,
      ));
    }
  }

  /// Normalize a file type string to our standard identifiers
  static String? _normalizeFileType(String type) {
    final lower = type.toLowerCase();
    switch (lower) {
      case 'nammodel':
      case 'nam':
        return 'nammodel';
      case 'aidadspmodel':
      case 'aidax':
      case 'aidiax':
        return 'aidadspmodel';
      case 'cabsim':
      case 'cab':
        return 'cabsim';
      case 'ir':
        return 'ir';
      case 'wav':
      case 'audio':
      case 'audiosample':
      case 'flac':
      case 'ogg':
        return 'audiosample';
      case 'sf2':
        return 'sf2';
      case 'sfz':
        return 'sfz';
      case 'json':
        // JSON can be AIDA-X model
        return 'aidadspmodel';
      case 'midi':
      case 'mid':
        return 'midifile';
      default:
        return lower;
    }
  }

  /// Convert MOD file type identifier to standard fileType
  static String? _modTypeToFileType(String modType) {
    // Map MOD type identifiers to file type strings used in file_types.dart
    switch (modType.toLowerCase()) {
      case 'sfzfile':
        return 'sfz';
      case 'sf2file':
        return 'sf2';
      case 'audiofile':
      case 'audiosample':
        return 'audiosample';
      case 'cabsimfile':
      case 'cabsimulatorfile':
        return 'cabsim';
      case 'irfile':
      case 'impulseresponsefile':
        return 'ir';
      case 'aidadspmodelfile':
        return 'aidadspmodel';
      case 'nammodelfile':
        return 'nammodel';
      case 'midifile':
        return 'midifile';
      default:
        // Try to match common patterns
        if (modType.toLowerCase().contains('audio')) return 'audiosample';
        if (modType.toLowerCase().contains('sfz')) return 'sfz';
        if (modType.toLowerCase().contains('sf2')) return 'sf2';
        if (modType.toLowerCase().contains('cab')) return 'cabsim';
        if (modType.toLowerCase().contains('ir')) return 'ir';
        if (modType.toLowerCase().contains('aida')) return 'aidadspmodel';
        if (modType.toLowerCase().contains('nam')) return 'nammodel';
        return modType.toLowerCase();
    }
  }
}
