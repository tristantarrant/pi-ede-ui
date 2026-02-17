import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:logging/logging.dart';
import 'package:rdflib/rdflib.dart';

final _log = Logger('Pedal');

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
    double? currentValue,
  }) : currentValue = currentValue ?? defaultValue;

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

  // Plugin metadata (loaded from LV2 bundle)
  String? label;
  String? brand;
  String? thumbnailPath;
  List<ControlPort>? controlPorts;

  Pedal({
    required this.instanceName,
    required this.pluginUri,
    required this.instanceNumber,
    required this.enabled,
    Map<String, double>? portValues,
  }) : portValues = portValues ?? {};

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
          currentValue: currentVal,
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

  LV2PluginInfo({
    required this.uri,
    required this.bundlePath,
    this.label,
    this.brand,
    this.thumbnailPath,
    List<ControlPort>? controlPorts,
  }) : controlPorts = controlPorts ?? [];

  Map<String, dynamic> toJson() => {
    'uri': uri,
    'bundlePath': bundlePath,
    'label': label,
    'brand': brand,
    'thumbnailPath': thumbnailPath,
    'controlPorts': controlPorts.map((p) => p.toJson()).toList(),
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

    return LV2PluginInfo(
      uri: uri,
      bundlePath: bundlePath,
      label: label,
      brand: brand,
      thumbnailPath: thumbnailPath,
      controlPorts: controlPorts,
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

  /// Load control ports synchronously
  static List<ControlPort> _loadControlPortsSync(String uri, String bundlePath) {
    final ports = <ControlPort>[];
    final manifestFile = File('$bundlePath/manifest.ttl');
    if (!manifestFile.existsSync()) return ports;

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
          final ttlPath = '$bundlePath/${ref.value}';
          final ttlFile = File(ttlPath);
          if (ttlFile.existsSync()) {
            _parseControlPortsFromTtlSync(uri, ttlFile, ports);
          }
        }
      }
    } catch (e) {
      // Skip problematic files
    }

    return ports;
  }

  /// Parse control ports from TTL file
  static void _parseControlPortsFromTtlSync(
      String pluginUri, File ttlFile, List<ControlPort> ports) {
    try {
      final g = Graph();
      g.parseTurtle(ttlFile.readAsStringSync());

      // Find all port definitions
      final portTriples = g.triples.where((t) =>
          t.sub.value == pluginUri &&
          t.pre.value == 'http://lv2plug.in/ns/lv2core#port');

      for (final portTriple in portTriples) {
        final portNode = portTriple.obj;

        // Check if it's a control port
        final typeTriples = g.triples.where((t) =>
            t.sub == portNode &&
            t.pre.value == 'http://www.w3.org/1999/02/22-rdf-syntax-ns#type');

        bool isControlPort = false;
        bool isOutputPort = false;

        for (final typeTriple in typeTriples) {
          final typeVal = typeTriple.obj.value;
          if (typeVal == 'http://lv2plug.in/ns/lv2core#ControlPort') {
            isControlPort = true;
          } else if (typeVal == 'http://lv2plug.in/ns/lv2core#OutputPort') {
            isOutputPort = true;
          }
        }

        if (!isControlPort) continue;

        // Get port properties
        String? symbol;
        String? name;
        double minimum = 0;
        double maximum = 1;
        double defaultValue = 0;
        bool isToggled = false;
        bool isInteger = false;
        bool isTrigger = false;

        for (final propTriple in g.triples.where((t) => t.sub == portNode)) {
          final pred = propTriple.pre.value;
          final obj = propTriple.obj;

          switch (pred) {
            case 'http://lv2plug.in/ns/lv2core#symbol':
              symbol = (obj as Literal).value;
              break;
            case 'http://lv2plug.in/ns/lv2core#name':
              name = (obj as Literal).value;
              break;
            case 'http://lv2plug.in/ns/lv2core#minimum':
              minimum = double.tryParse((obj as Literal).value) ?? 0;
              break;
            case 'http://lv2plug.in/ns/lv2core#maximum':
              maximum = double.tryParse((obj as Literal).value) ?? 1;
              break;
            case 'http://lv2plug.in/ns/lv2core#default':
              defaultValue = double.tryParse((obj as Literal).value) ?? 0;
              break;
            case 'http://lv2plug.in/ns/lv2core#portProperty':
              final propVal = obj.value;
              if (propVal == 'http://lv2plug.in/ns/lv2core#toggled') {
                isToggled = true;
              } else if (propVal == 'http://lv2plug.in/ns/lv2core#integer') {
                isInteger = true;
              } else if (propVal == 'http://lv2plug.in/ns/ext/port-props#trigger') {
                isTrigger = true;
              }
              break;
          }
        }

        if (symbol != null) {
          ports.add(ControlPort(
            symbol: symbol,
            name: name ?? symbol,
            minimum: minimum,
            maximum: maximum,
            defaultValue: defaultValue,
            isToggled: isToggled,
            isInteger: isInteger,
            isTrigger: isTrigger,
            isOutput: isOutputPort,
          ));
        }
      }
    } catch (e) {
      // Skip problematic files
    }
  }
}
