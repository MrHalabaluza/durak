import 'dart:io';

typedef HttpHandler = Future<void> Function(
    HttpRequest req, Map<String, String> params);

class Route {
  final String method;
  final List<String> segments;
  final HttpHandler handler;

  Route(this.method, String pattern, this.handler)
      : segments =
            pattern.split('/').where((s) => s.isNotEmpty).toList();

  Map<String, String>? match(String method, List<String> reqSegs) {
    if (method != this.method) return null;
    if (reqSegs.length != segments.length) return null;
    final params = <String, String>{};
    for (var i = 0; i < segments.length; i++) {
      if (segments[i].startsWith(':')) {
        params[segments[i].substring(1)] = reqSegs[i];
      } else if (segments[i] != reqSegs[i]) {
        return null;
      }
    }
    return params;
  }
}

class Router {
  final List<Route> _routes = [];

  void add(String method, String pattern, HttpHandler h) =>
      _routes.add(Route(method, pattern, h));

  Future<bool> dispatch(HttpRequest req) async {
    final segs = req.uri.pathSegments;
    for (final r in _routes) {
      final p = r.match(req.method, segs);
      if (p != null) {
        await r.handler(req, p);
        return true;
      }
    }
    return false;
  }
}
