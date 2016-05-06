// Copyright (c) 2016 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:dashboard_box/src/utils.dart';

Future<Null> main() async {
  await exec('dart2js', [
    '--enable-experimental-mirrors',
    '-osite/analysis.dart.js',
    'site/analysis.dart'
  ]);

  rm(new File('site/analysis.dart.js.deps'));
  rm(new File('site/analysis.dart.js.map'));
}
