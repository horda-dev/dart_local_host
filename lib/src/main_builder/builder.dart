import 'dart:async';

import 'package:build/build.dart';
import 'package:glob/glob.dart';
import 'package:path/path.dart' as path;
import 'package:source_gen/source_gen.dart';

import 'analyzed_package.dart';
import 'generator.dart';

Builder mainBuilder(BuilderOptions options) => MainBuilder();

class MainBuilder implements Builder {
  @override
  FutureOr<void> build(BuildStep buildStep) async {
    final analyzedPackage = await _run(
      buildStep.resolver,
      buildStep.findAssets(
        Glob('lib/**/*.dart'),
      ),
    );

    final mainFuncActors = analyzedPackage.actors.values
        .map(
          (actor) => MainFuncActor(
            actor.name,
            actor.state.name,
            actor.viewGroup.name,
          ),
        )
        .toList();
    final mainFuncServices = analyzedPackage.services.values
        .map((service) => MainFuncService(service.name))
        .toList();
    final mainFuncProcesses = analyzedPackage.processGroups.values
        .map((process) => MainFuncProcess(process.name))
        .toList();

    // Write output
    await buildStep.writeAsString(
      AssetId(
        buildStep.inputId.package,
        path.joinAll([
          'bin',
          'main.dart',
        ]),
      ),
      generateMainFile(
        buildStep.inputId.package,
        mainFuncActors,
        mainFuncServices,
        mainFuncProcesses,
      ),
    );
  }

  @override
  Map<String, List<String>> get buildExtensions => {
    r'$package$': ['bin/main.dart'],
  };

  Future<AnalyzedPackage> _run(
    Resolver resolver,
    Stream<AssetId> assets,
  ) async {
    final analyzedPackage = AnalyzedPackage();

    await for (final assetId in assets) {
      final isLibrary = await resolver.isLibrary(assetId);
      if (!isLibrary) {
        continue;
      }

      final lib = await resolver.libraryFor(assetId, allowSyntaxErrors: true);

      final reader = LibraryReader(lib);

      analyzedPackage.read(reader);
    }

    analyzedPackage.linkStatesAndViewGroupsToActors();

    return analyzedPackage;
  }
}
