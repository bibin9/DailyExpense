import 'dart:io';

import 'package:det_admin/det_admin.dart';

void main(List<String> args) {
  try {
    exitCode = Admin(out: stdout).run(args);
  } on CliException catch (e) {
    stderr.writeln('Error: ${e.message}');
    exitCode = e.exitCode;
  } on FormatException catch (e) {
    stderr.writeln('Error: ${e.message}');
    exitCode = 65;
  }
}
