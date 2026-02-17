import 'dart:io';

import 'package:logging/logging.dart';
import 'package:rdflib/rdflib.dart';

final _log = Logger('Pedal');

/// Represents an LV2 plugin instance within a pedalboard
class Pedal {
  final String instanceName;
  final String pluginUri;
  final int instanceNumber;
  final bool enabled;

  // Plugin metadata (loaded from LV2 bundle)
  String? label;
  String? brand;
  String? thumbnailPath;

  Pedal({
    required this.instanceName,
    required this.pluginUri,
    required this.instanceNumber,
    required this.enabled,
  });

  /// Load plugin metadata from its LV2 bundle
  Future<void> loadMetadata(LV2PluginCache cache) async {
    final info = await cache.getPluginInfo(pluginUri);
    if (info != null) {
      label = info.label;
      brand = info.brand;
      thumbnailPath = info.thumbnailPath;
    }
  }

  @override
  String toString() => 'Pedal($instanceName: $pluginUri)';
}

/// Information about an LV2 plugin from its modgui.ttl
class LV2PluginInfo {
  final String uri;
  final String bundlePath;
  final String? label;
  final String? brand;
  final String? thumbnailPath;

  LV2PluginInfo({
    required this.uri,
    required this.bundlePath,
    this.label,
    this.brand,
    this.thumbnailPath,
  });
}

/// Cache for LV2 plugin information
class LV2PluginCache {
  static LV2PluginCache? _instance;
  final Map<String, LV2PluginInfo> _cache = {};
  bool _initialized = false;

  LV2PluginCache._();

  static LV2PluginCache get instance {
    _instance ??= LV2PluginCache._();
    return _instance!;
  }

  /// Get plugin info by URI
  Future<LV2PluginInfo?> getPluginInfo(String uri) async {
    if (!_initialized) {
      await _scanPlugins();
    }
    return _cache[uri];
  }

  /// Scan all LV2 directories for plugins
  Future<void> _scanPlugins() async {
    if (_initialized) return;

    final lv2Paths = <String>[
      '/usr/lib/lv2',
      '/usr/local/lib/lv2',
      '${Platform.environment['HOME']}/.lv2',
    ];

    for (final lv2Path in lv2Paths) {
      final dir = Directory(lv2Path);
      if (!await dir.exists()) continue;

      await for (final bundle in dir.list()) {
        if (bundle is Directory && bundle.path.endsWith('.lv2')) {
          await _scanBundle(bundle.path);
        }
      }
    }

    _initialized = true;
    _log.info('LV2 plugin cache initialized with ${_cache.length} plugins');
  }

  /// Scan a single LV2 bundle
  Future<void> _scanBundle(String bundlePath) async {
    final manifestFile = File('$bundlePath/manifest.ttl');
    if (!await manifestFile.exists()) return;

    try {
      final g = Graph();
      g.parseTurtle(await manifestFile.readAsString());

      // Find all plugins in this bundle
      final pluginTriples = g.triples.where((t) =>
          t.pre.value == 'http://www.w3.org/1999/02/22-rdf-syntax-ns#type' &&
          t.obj.value == 'http://lv2plug.in/ns/lv2core#Plugin');

      for (final triple in pluginTriples) {
        final uri = triple.sub.value;
        await _loadPluginModGui(uri, bundlePath);
      }
    } catch (e) {
      _log.warning('Failed to scan bundle $bundlePath: $e');
    }
  }

  /// Load modgui.ttl for a plugin
  Future<void> _loadPluginModGui(String uri, String bundlePath) async {
    final modguiFile = File('$bundlePath/modgui.ttl');

    String? label;
    String? brand;
    String? thumbnailPath;

    if (await modguiFile.exists()) {
      try {
        final g = Graph();
        g.parseTurtle(await modguiFile.readAsString());

        // Find modgui:label
        final labelTriples = g.triples.where((t) =>
            t.pre.value == 'http://moddevices.com/ns/modgui#label');
        if (labelTriples.isNotEmpty) {
          label = (labelTriples.first.obj as Literal).value;
        }

        // Find modgui:brand
        final brandTriples = g.triples.where((t) =>
            t.pre.value == 'http://moddevices.com/ns/modgui#brand');
        if (brandTriples.isNotEmpty) {
          brand = (brandTriples.first.obj as Literal).value;
        }

        // Find modgui:thumbnail
        final thumbTriples = g.triples.where((t) =>
            t.pre.value == 'http://moddevices.com/ns/modgui#thumbnail');
        if (thumbTriples.isNotEmpty) {
          final thumbRef = thumbTriples.first.obj;
          if (thumbRef is URIRef) {
            // Resolve relative path
            thumbnailPath = '$bundlePath/${thumbRef.value}';
          }
        }
      } catch (e) {
        _log.warning('Failed to parse modgui.ttl for $uri: $e');
      }
    }

    // If no label from modgui, try to extract from URI
    label ??= uri.split('/').last.split('#').last;

    _cache[uri] = LV2PluginInfo(
      uri: uri,
      bundlePath: bundlePath,
      label: label,
      brand: brand,
      thumbnailPath: thumbnailPath,
    );
  }
}
