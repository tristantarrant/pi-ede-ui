import 'dart:io';

import 'package:rdflib/rdflib.dart';

class Pedalboard {
  final String name;
  final String path;

  Pedalboard(this.name, this.path);

  factory Pedalboard.load(FileSystemEntity f) {
    Graph g = Graph();
    g.parseTurtle(File("${f.path}/manifest.ttl").readAsStringSync());
    var triples = g.matchTriples("http://www.w3.org/2000/01/rdf-schema#seeAlso");
    var uri = triples.first.obj as URIRef;
    g = Graph();
    g.parseTurtle(File("${f.path}/${uri.value}").readAsStringSync());
    triples = g.matchTriples("http://usefulinc.com/ns/doap#name");
    var name = triples.first.obj as Literal;
    return Pedalboard(name.value, f.path);
  }
}