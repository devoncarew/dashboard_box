// Copyright 2015 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:stack_trace/stack_trace.dart';

import 'package:dashboard_box/src/utils.dart';
import 'package:dashboard_box/src/firebase_uploader.dart';

Future<Null> main(List<String> args) async {
  if (args.length != 1)
    fail('Expects a single argument pointing to the root directory of the dashboard but got: ${args}');

  config = new Config(path.normalize(path.absolute(args.single)));

  Chain.capture(() async {
    section('Build started on ${new DateTime.now()}');
    print(config);

    if (!exists(config.dataDirectory))
      rrm(config.dataDirectory);

    mkdirs(config.dataDirectory);

    await build();

    section('Build finished on ${new DateTime.now()}');
  }, onError: (error, Chain chain) {
    print(error);
    print(chain.terse);
    exit(1);
  });
}

Future<Null> build() async {
  await prepareDataDirectory();
  await getFlutter();
  await runPerfTests();
  await runStartupTests();
  await runAnalyzerTests();
  await generateBuildInfo();
  await uploadDataToFirebase();
}

Future<Null> prepareDataDirectory() async {
  // Backup old data
  if (!exists(config.backupDirectory))
    mkdirs(config.backupDirectory);

  if (!exists(config.dataDirectory))
    move(config.dataDirectory, to: config.backupDirectory);

  mkdir(config.dataDirectory);
}

Future<Null> getFlutter() async {
  section('Get Flutter!');

  cd(config.rootDirectory);
  if (exists(config.flutterDirectory))
    rrm(config.flutterDirectory);

  await exec('git', ['clone', '--depth', '1', 'https://github.com/flutter/flutter.git']);
  await flutter('config', options: ['--no-analytics']);

  section('flutter doctor');
  await flutter('doctor');

  section('flutter update-packages');
  await flutter('update-packages');
}

Future<Null> runPerfTests() async {
  section('Run perf tests');

  await runTest('${config.flutterDirectory.path}/examples/stocks', 'test_driver/scroll_perf.dart', 'stocks_scroll_perf');
  await runTest('${config.flutterDirectory.path}/dev/benchmarks/complex_layout', 'test_driver/scroll_perf.dart', 'complex_layout_scroll_perf');
}

Future<Null> runStartupTests() async {
  section('Run startup tests');

  await runStartupTest('${config.flutterDirectory.path}/examples/stocks', 'stocks');
  await runStartupTest('${config.flutterDirectory.path}/dev/benchmarks/complex_layout', 'complex_layout');
}

Future<int> runTest(String testDirectory, String testTarget, String testName) {
  return inDirectory(testDirectory, () async {
    await pub('get');
    await flutter('drive', options: [
      '--verbose',
      '--no-checked',
      '-t',
      testTarget,
      '-d',
      config.androidDeviceId
    ]);
    copy(file('${testDirectory}/build/${testName}.timeline_summary.json'),
        config.dataDirectory, name: '${testName}__timeline_summary.json');
  });
}

Future<int> runStartupTest(String testDirectory, String testName) {
  return inDirectory(testDirectory, () async {
    await pub('get');
    await flutter('run', options: [
      '--verbose',
      '--no-checked',
      '--trace-startup',
      '-d',
      config.androidDeviceId
    ]);
    copy(file('${testDirectory}/build/start_up_info.json'),
        config.dataDirectory, name: '${testName}__start_up.json');
  });
}

Future<Null> runAnalyzerTests() async {
  DateTime now = new DateTime.now();
  String sdk = await getDartVersion();
  String commit = await getFlutterRepoCommit();

  Benchmark benchmark = new FlutterAnalyzeBenchmark(now, sdk, commit);
  section(benchmark.name);
  await runBenchmark(benchmark, iterations: 3);

  benchmark = new FlutterAnalyzeAppBenchmark(now, sdk, commit);
  section(benchmark.name);
  await runBenchmark(benchmark, iterations: 3);
}

class FlutterAnalyzeBenchmark extends Benchmark {
  FlutterAnalyzeBenchmark(this.time, this.sdk, this.commit) : super('flutter analyze --flutter-repo');

  final DateTime time;
  final String sdk;
  final String commit;

  File get benchmarkFile => file(path.join(config.flutterDirectory.path, 'analysis_benchmark.json'));

  @override
  Future<num> run() async {
    rm(benchmarkFile);
    await inDirectory(config.flutterDirectory, () async {
      await flutter('analyze', options: ['--flutter-repo', '--benchmark']);
    });
    return _patchupAnalysisResult(benchmarkFile, time, expected: 25.0, sdk: sdk, commit: commit);
  }

  @override
  void markLastRunWasBest(num result) {
    copy(benchmarkFile, config.dataDirectory, name: 'analyzer_cli__analysis_time.json');
  }
}

class FlutterAnalyzeAppBenchmark extends Benchmark {
  FlutterAnalyzeAppBenchmark(this.time, this.sdk, this.commit) : super('analysis server mega_gallery');

  final DateTime time;
  final String sdk;
  final String commit;

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
    return _patchupAnalysisResult(benchmarkFile, time, expected: 20.0, sdk: sdk, commit: commit);
  }

  @override
  void markLastRunWasBest(num result) {
    copy(benchmarkFile, config.dataDirectory, name: 'analyzer_server__analysis_time.json');
  }
}

num _patchupAnalysisResult(File jsonFile, DateTime now, {
  double expected,
  String sdk,
  String commit
}) {
  Map<String, dynamic> json;
  if (jsonFile.existsSync())
    json = JSON.decode(jsonFile.readAsStringSync());
  else
    json = <String, dynamic>{};

  json['timestamp'] = now.millisecondsSinceEpoch;
  if (expected != null)
    json['expected'] = expected;
  if (sdk != null)
    json['sdk'] = sdk;
  if (commit != null)
    json['commit'] = expected;
  jsonFile.writeAsStringSync(jsonEncode(json));

  return json['time'];
}

Future<Null> generateBuildInfo() async {
  await config.buildInfoFile.writeAsString(jsonEncode({
    'build_timestamp': '${new DateTime.now()}',
    'dart_version': await getDartVersion()
  }));
}

Future<Null> uploadDataToFirebase() async {
  if (Platform.environment['UPLOAD_DASHBOARD_DATA'] != 'yes')
    return null;

  for (File file in ls(config.dataDirectory)) {
    await uploadToFirebase(file);
  }
}

abstract class Benchmark {
  Benchmark(this.name);

  final String name;

  Future<Null> init() => new Future.value();

  Future<num> run();

  void markLastRunWasBest(num result);

  String toString() => name;
}

Future<num> runBenchmark(Benchmark benchmark, { int iterations: 1 }) async {
  await benchmark.init();

  num minValue;

  while (iterations > 0) {
    iterations--;

    print('');

    num result = await benchmark.run();

    if (minValue == null || result < minValue) {
      benchmark.markLastRunWasBest(result);
      minValue = result;
    }
  }

  return minValue;
}
