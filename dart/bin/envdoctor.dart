/// envdoctor CLI entrypoint.
library;

import 'dart:io';

import 'package:envdoctor/src/cli.dart' as cli;

void main(List<String> args) {
  exitCode = cli.run(args);
}
