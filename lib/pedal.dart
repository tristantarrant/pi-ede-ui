import 'dart:io';

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

  /// Load modgui.ttl and control ports for a plugin
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

    // Load control ports from the main plugin TTL
    final controlPorts = await _loadControlPorts(uri, bundlePath);

    _cache[uri] = LV2PluginInfo(
      uri: uri,
      bundlePath: bundlePath,
      label: label,
      brand: brand,
      thumbnailPath: thumbnailPath,
      controlPorts: controlPorts,
    );
  }

  /// Load control ports from the plugin's main TTL file
  Future<List<ControlPort>> _loadControlPorts(String uri, String bundlePath) async {
    final ports = <ControlPort>[];

    // Find the main TTL file from manifest
    final manifestFile = File('$bundlePath/manifest.ttl');
    if (!await manifestFile.exists()) return ports;

    try {
      final manifestGraph = Graph();
      manifestGraph.parseTurtle(await manifestFile.readAsString());

      // Find rdfs:seeAlso references for this plugin
      final seeAlsoTriples = manifestGraph.triples.where((t) =>
          t.sub.value == uri &&
          t.pre.value == 'http://www.w3.org/2000/01/rdf-schema#seeAlso');

      for (final seeAlso in seeAlsoTriples) {
        final ref = seeAlso.obj;
        if (ref is URIRef && !ref.value.contains('modgui')) {
          final ttlPath = '$bundlePath/${ref.value}';
          final ttlFile = File(ttlPath);
          if (await ttlFile.exists()) {
            await _parseControlPortsFromTtl(uri, ttlFile, ports);
          }
        }
      }
    } catch (e) {
      _log.warning('Failed to load control ports for $uri: $e');
    }

    return ports;
  }

  /// Parse control ports from a TTL file
  Future<void> _parseControlPortsFromTtl(
      String pluginUri, File ttlFile, List<ControlPort> ports) async {
    try {
      final g = Graph();
      g.parseTurtle(await ttlFile.readAsString());

      // Find all port definitions
      // Ports are typically blank nodes referenced from the plugin's lv2:port predicate
      final portTriples = g.triples.where((t) =>
          t.sub.value == pluginUri &&
          t.pre.value == 'http://lv2plug.in/ns/lv2core#port');

      for (final portTriple in portTriples) {
        final portNode = portTriple.obj;

        // Check if it's a control port and input/output port
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
      _log.warning('Failed to parse ports from ${ttlFile.path}: $e');
    }
  }
}
