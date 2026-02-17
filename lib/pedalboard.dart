import 'dart:io';

import 'package:logging/logging.dart';
import 'package:rdflib/rdflib.dart';
import 'package:pi_ede_ui/pedal.dart';

final _log = Logger('Pedalboard');

class Pedalboard {
  final String name;
  final String path;
  final String _ttlFileName;
  List<Pedal>? _pedals;

  Pedalboard(this.name, this.path, this._ttlFileName);

  factory Pedalboard.load(FileSystemEntity f) {
    Graph g = Graph();
    g.parseTurtle(File("${f.path}/manifest.ttl").readAsStringSync());
    var triples = g.matchTriples("http://www.w3.org/2000/01/rdf-schema#seeAlso");
    var uri = triples.first.obj as URIRef;
    g = Graph();
    g.parseTurtle(File("${f.path}/${uri.value}").readAsStringSync());
    triples = g.matchTriples("http://usefulinc.com/ns/doap#name");
    var name = triples.first.obj as Literal;
    return Pedalboard(name.value, f.path, uri.value);
  }

  /// Load and return the list of pedals in this pedalboard
  Future<List<Pedal>> getPedals() async {
    if (_pedals != null) return _pedals!;

    _pedals = [];
    try {
      final g = Graph();
      g.parseTurtle(File("$path/$_ttlFileName").readAsStringSync());

      // Find all ingen:Block instances (plugins)
      final blockTriples = g.triples.where((t) =>
          t.pre.value == 'http://www.w3.org/1999/02/22-rdf-syntax-ns#type' &&
          t.obj.value == 'http://drobilla.net/ns/ingen#Block');

      for (final blockTriple in blockTriples) {
        final instanceName = blockTriple.sub.value;

        // Find the prototype URI for this block
        final protoTriples = g.triples.where((t) =>
            t.sub.value == instanceName &&
            t.pre.value == 'http://lv2plug.in/ns/lv2core#prototype');

        if (protoTriples.isEmpty) continue;

        final pluginUri = protoTriples.first.obj.value;

        // Find instance number
        final instanceNumTriples = g.triples.where((t) =>
            t.sub.value == instanceName &&
            t.pre.value == 'http://moddevices.com/ns/modpedal#instanceNumber');

        int instanceNumber = 0;
        if (instanceNumTriples.isNotEmpty) {
          final numLiteral = instanceNumTriples.first.obj as Literal;
          instanceNumber = int.tryParse(numLiteral.value) ?? 0;
        }

        // Find enabled state
        final enabledTriples = g.triples.where((t) =>
            t.sub.value == instanceName &&
            t.pre.value == 'http://drobilla.net/ns/ingen#enabled');

        bool enabled = true;
        if (enabledTriples.isNotEmpty) {
          final enabledVal = enabledTriples.first.obj;
          if (enabledVal is Literal) {
            enabled = enabledVal.value == 'true';
          }
        }

        _pedals!.add(Pedal(
          instanceName: instanceName,
          pluginUri: pluginUri,
          instanceNumber: instanceNumber,
          enabled: enabled,
        ));
      }

      // Sort by instance number
      _pedals!.sort((a, b) => a.instanceNumber.compareTo(b.instanceNumber));

      // Load metadata for all pedals
      final cache = LV2PluginCache.instance;
      for (final pedal in _pedals!) {
        await pedal.loadMetadata(cache);
      }

      _log.info('Loaded ${_pedals!.length} pedals from $name');
    } catch (e) {
      _log.warning('Failed to load pedals from $path: $e');
    }

    return _pedals!;
  }
}