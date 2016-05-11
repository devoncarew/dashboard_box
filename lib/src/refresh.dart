// Copyright (c) 2016 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as path;

import 'benchmarks.dart';
import 'utils.dart';

Future<Null> runRefreshTests() async {
  String sdk = await getDartVersion();
  String commit = await getFlutterRepoCommit();
  DateTime time = await getFlutterRepoCommitTimestamp(commit);

  Benchmark benchmark = new EditRefreshBenchmark(time, sdk, commit);
  section(benchmark.name);
  await runBenchmark(benchmark, iterations: 3);
}

class EditRefreshBenchmark extends Benchmark {
  EditRefreshBenchmark(this.time, this.sdk, this.commit) : super('edit refresh');

  final DateTime time;
  final String sdk;
  final String commit;

  Directory get megaDir => dir(path.join(config.flutterDirectory.path, 'dev/benchmarks/mega_gallery'));
  File get benchmarkFile => file(path.join(megaDir.path, 'refresh_benchmark.json'));

  Future<Null> init() {
    return inDirectory(config.flutterDirectory, () async {
      await dart(['dev/tools/mega_gallery.dart']);
    });
  }

  @override
  Future<num> run() async {
    rm(benchmarkFile);
    int exitCode = await inDirectory(megaDir, () async {
      return await flutter('run', options: ['-d', config.androidDeviceId, '--benchmark']);
    });
    if (exitCode != 0)
      return new Future.error(exitCode);
    return patchupResultFile(benchmarkFile, timestamp: time, expected: 10.0, sdk: sdk, commit: commit);
  }

  @override
  void markLastRunWasBest(num result, List<num> allRuns) {
    copy(benchmarkFile, config.dataDirectory, name: 'mega_gallery__refresh_time.json');
  }
}
