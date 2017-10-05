// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:build_compilers/build_compilers.dart';
import 'package:build_runner/build_runner.dart';

Future<Null> main() async {
  await watch(
    [
      new BuildAction(
        new LinkedSummaryBuilder(),
        'web_simple_ddc',
        inputs: const ['web/**.dart'],
      ),
      new BuildAction(
        new DevCompilerBuilder(),
        'web_simple_ddc',
        inputs: const ['web/**.dart'],
      ),
    ],
    deleteFilesByDefault: true,
    writeToCache: true,
  );
  // TODO: Serve from the generated directory.
}
