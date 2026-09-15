import '../models/finding.dart';
import '../utils/json.dart';
import '../utils/paths.dart';

/// Render a scan result as the reference CLI's JSON shape (camelCase
/// projection, `JSON.stringify(x, null, 2)` formatting).
String renderScanJson(
    String root, List<Finding> findings, AuditSummary summary, int exitCode) {
  final findingsJson = findings.map((f) {
    final locations = f.locations.map((o) {
      final loc = JsonObject()
        ..add('file', displayPath(root, o.filePath));
      final line = o.line;
      if (line != null) loc.add('line', line);
      loc.add('kind', o.kind.str);
      return loc;
    }).toList();
    return JsonObject()
      ..add('id', f.id)
      ..add('ruleId', f.ruleId)
      ..add('severity', f.severity.str)
      ..add('variable', f.variable)
      ..add('message', f.message)
      ..add('locations', locations);
  }).toList();

  return jsonPretty(JsonObject()
    ..add('exitCode', exitCode)
    ..add('summary', JsonObject()
      ..add('filesScanned', summary.filesScanned)
      ..add('variablesFound', summary.variablesFound)
      ..add('errors', summary.errors)
      ..add('warnings', summary.warnings)
      ..add('infos', summary.infos)
      ..add('total', summary.total))
    ..add('findings', findingsJson));
}
