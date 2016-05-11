// Copyright (c) 2016 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as path;

import 'benchmarks.dart';
import 'utils.dart';

Future<Null> runAnalyzerTests({
  String sdk,
  String commit,
  DateTime timestamp
}) async {
  Benchmark benchmark = new FlutterAnalyzeBenchmark(sdk, commit, timestamp);
  section(benchmark.name);
  await runBenchmark(benchmark, iterations: 3);

  benchmark = new FlutterAnalyzeAppBenchmark(sdk, commit, timestamp);
  section(benchmark.name);
  await runBenchmark(benchmark, iterations: 3);
}

class FlutterAnalyzeBenchmark extends Benchmark {
  FlutterAnalyzeBenchmark(this.sdk, this.commit, this.timestamp) : super('flutter analyze --flutter-repo');

  final String sdk;
  final String commit;
  final DateTime timestamp;

  File get benchmarkFile => file(path.join(config.flutterDirectory.path, 'analysis_benchmark.json'));

  @override
  Future<num> run() async {
    rm(benchmarkFile);
    await inDirectory(config.flutterDirectory, () async {
      await flutter('analyze', options: ['--flutter-repo', '--benchmark']);
    });
    return addBuildInfo(benchmarkFile, timestamp: timestamp, expected: 25.0, sdk: sdk, commit: commit);
  }

  @override
  void markLastRunWasBest(num result, List<num> allRuns) {
    copy(benchmarkFile, config.dataDirectory, name: 'analyzer_cli__analysis_time.json');
  }
}

class FlutterAnalyzeAppBenchmark extends Benchmark {
  FlutterAnalyzeAppBenchmark(this.sdk, this.commit, this.timestamp) : super('analysis server mega_gallery');

  final String sdk;
  final String commit;
  final DateTime timestamp;

  Directory get megaDir => dir(path.join(config.flutterDirectory.path, 'dev/benchmarks/mega_gallery'));
  File get benchmarkFile => file(path.join(megaDir.path, 'analysis_benchmark.json'));

  Future<Null> init() {
    return inDirectory(config.flutterDirectory, () async {
      await dart(['dev/tools/mega_gallery.dart']);
    });
  }

  @override
  Future<num> run() async {
    rm(benchmarkFile);
    await inDirectory(megaDir, () async {
      await flutter('analyze', options: ['--watch', '--benchmark']);
    });
    return addBuildInfo(benchmarkFile, timestamp: timestamp, expected: 10.0, sdk: sdk, commit: commit);
  }

  @override
  void markLastRunWasBest(num result, List<num> allRuns) {
    copy(benchmarkFile, config.dataDirectory, name: 'analyzer_server__analysis_time.json');
  }
}
