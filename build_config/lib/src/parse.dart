// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:build/build.dart';
import 'package:yaml/yaml.dart';

import 'build_config.dart';
import 'key_normalization.dart';

const _targetOptions = const [
  _builders,
  _dependencies,
  _sources,
];
const _builders = 'builders';
const _dependencies = 'dependencies';
const _sources = 'sources';

const _builderConfigOptions = const [
  _generateFor,
  _enabled,
  _options,
];
const _generateFor = 'generate_for';
const _enabled = 'enabled';
const _options = 'options';

const _builderDefinitionOptions = const [
  _builderFactories,
  _import,
  _buildExtensions,
  _target,
  _autoApply,
  _requiredInputs,
  _isOptional,
  _buildTo,
  _defaults,
];
const _builderFactories = 'builder_factories';
const _import = 'import';
const _buildExtensions = 'build_extensions';
const _target = 'target';
const _autoApply = 'auto_apply';
const _requiredInputs = 'required_inputs';
const _isOptional = 'is_optional';
const _buildTo = 'build_to';
const _defaults = 'defaults';
const _builderConfigDefaultOptions = const [
  _generateFor,
];

BuildConfig parseFromYaml(
        String packageName, Iterable<String> dependencies, String configYaml) =>
    parseFromMap(packageName, dependencies,
        loadYaml(configYaml) as Map<String, dynamic> ?? {});

BuildConfig parseFromMap(String packageName,
    Iterable<String> packageDependencies, Map<String, dynamic> config) {
  assert(packageName != null);
  assert(packageDependencies != null);

  final buildTargets = <String, BuildTarget>{};
  final builderDefinitions = <String, BuilderDefinition>{};

  final Map<String, Map> targetConfigs =
      config['targets'] as Map<String, Map> ?? {};
  for (var targetName in targetConfigs.keys) {
    var targetConfig = _readMapOrThrow(
        targetConfigs, targetName, _targetOptions, 'target `$targetName`');

    final builders = _readBuildersOrThrow(packageName, targetConfig, _builders);

    final dependencies = _readListOfStringsOrThrow(targetConfig, _dependencies,
            defaultValue: packageDependencies)
        .map((dep) => normalizeTargetKeyUsage(dep, packageName))
        .toSet();

    final sources = _readInputSetOrThrow(targetConfig, _sources,
        defaultValue: const InputSet());

    final targetKey = normalizeTargetKeyDefinition(targetName, packageName);
    buildTargets[targetKey] = new BuildTarget(
      builders: builders,
      dependencies: dependencies,
      package: packageName,
      key: targetKey,
      sources: sources,
    );
  }

  final defaultTarget = '$packageName:$packageName';
  if (buildTargets.isEmpty) {
    // Add the default dart library if there are no targets discovered.
    buildTargets[defaultTarget] = new BuildTarget(
      dependencies: packageDependencies
          .map((dep) => normalizeTargetKeyUsage(dep, packageName))
          .toSet(),
      package: packageName,
      key: defaultTarget,
      sources: const InputSet(),
    );
  }

  if (!buildTargets.containsKey(defaultTarget)) {
    throw new ArgumentError('Must specify a target with the name '
        '$packageName or `\$default`');
  }

  final Map<String, Map> builderConfigs =
      config['builders'] as Map<String, Map> ?? {};
  for (var builderName in builderConfigs.keys) {
    final builderConfig = _readMapOrThrow(builderConfigs, builderName,
        _builderDefinitionOptions, 'builder `$builderName`',
        defaultValue: <String, dynamic>{});

    final builderFactories =
        _readListOfStringsOrThrow(builderConfig, _builderFactories);
    final import = _readStringOrThrow(builderConfig, _import);
    final buildExtensions = _readBuildExtensions(builderConfig);
    final target = normalizeTargetKeyUsage(
        _readStringOrThrow(builderConfig, _target), packageName);
    final autoApply = _readAutoApplyOrThrow(builderConfig, _autoApply,
        defaultValue: AutoApply.none);
    final requiredInputs = _readListOfStringsOrThrow(
        builderConfig, _requiredInputs,
        defaultValue: const []);
    final isOptional =
        _readBoolOrThrow(builderConfig, _isOptional, defaultValue: false);

    final buildTo = _readBuildToOrThrow(builderConfig, _buildTo,
        defaultValue: BuildTo.cache);

    final defaultOptions = _readMapOrThrow(
        builderConfig, _defaults, _builderConfigDefaultOptions, 'defaults',
        defaultValue: {});
    final defaultGenerateFor =
        _readInputSetOrThrow(defaultOptions, _generateFor, allowNull: true);

    final builderKey = normalizeBuilderKeyDefinition(builderName, packageName);
    builderDefinitions[builderKey] = new BuilderDefinition(
      key: builderKey,
      builderFactories: builderFactories,
      import: import,
      buildExtensions: buildExtensions,
      package: packageName,
      target: target,
      autoApply: autoApply,
      requiredInputs: requiredInputs,
      isOptional: isOptional,
      buildTo: buildTo,
      defaults:
          new TargetBuilderConfigDefaults(generateFor: defaultGenerateFor),
    );
  }
  return new BuildConfig(
      packageName: packageName,
      buildTargets: buildTargets,
      builderDefinitions: builderDefinitions);
}

Map<String, List<String>> _readBuildExtensions(Map<String, dynamic> options) {
  dynamic value = options[_buildExtensions];
  if (value == null) {
    throw new ArgumentError('Missing configuratino for build_extensions');
  }
  if (value is! Map<String, List<String>>) {
    throw new ArgumentError('Invalid value for build_extensions, '
        'got `$value` but expected a Map');
  }
  return value as Map<String, List<String>>;
}

Map<String, dynamic> _readMapOrThrow(Map<String, dynamic> options,
    String option, Iterable<String> validKeys, String description,
    {Map<String, dynamic> defaultValue}) {
  var value = options[option] ?? defaultValue;
  if (value is! Map) {
    throw new ArgumentError('Invalid options for `$option`, got `$value` but '
        'expected a Map.');
  }
  var mapValue = value as Map<String, dynamic>;
  var invalidOptions = mapValue.keys.toList()
    ..removeWhere((k) => validKeys.contains(k));
  if (invalidOptions.isNotEmpty) {
    throw new ArgumentError('Got invalid options `$invalidOptions` for '
        '$description. Only `$validKeys` are supported keys.');
  }
  return mapValue;
}

String _readStringOrThrow(Map<String, dynamic> options, String option,
    {String defaultValue, bool allowNull: false}) {
  var value = options[option];
  if (value == null && allowNull) return null;
  if (value is! String) {
    throw new ArgumentError(
        'Expected a String for `$option` but got `$value`.');
  }
  return value as String;
}

bool _readBoolOrThrow(Map<String, dynamic> options, String option,
    {bool defaultValue, bool allowNull: false}) {
  var value = options[option] ?? defaultValue;
  // ignore: avoid_returning_null
  if (value == null && allowNull) return null;
  if (value is! bool) {
    throw new ArgumentError(
        'Expected a boolean for `$option` but got `$value`.');
  }
  return value as bool;
}

AutoApply _readAutoApplyOrThrow(Map<String, dynamic> options, String option,
    {AutoApply defaultValue}) {
  final value = options[option];
  if (value == null && defaultValue != null) return defaultValue;
  final allowedValues = const {
    'none': AutoApply.none,
    'dependents': AutoApply.dependents,
    'all_packages': AutoApply.allPackages,
    'root_package': AutoApply.rootPackage
  };
  if (value is! String || !allowedValues.containsKey(value)) {
    throw new ArgumentError('Expected one of ${allowedValues.keys.toList()} '
        'for `$option` but got `$value`');
  }
  return allowedValues[value];
}

BuildTo _readBuildToOrThrow(Map<String, dynamic> options, String option,
    {BuildTo defaultValue}) {
  final value = options[option];
  if (value == null && defaultValue != null) return defaultValue;
  final allowedValues = const {
    'source': BuildTo.source,
    'cache': BuildTo.cache,
  };
  if (value is! String || !allowedValues.containsKey(value)) {
    throw new ArgumentError('Expected one of ${allowedValues.keys.toList()} '
        'for `$option` but got `$value`');
  }
  return allowedValues[value];
}

Map<String, TargetBuilderConfig> _readBuildersOrThrow(
    String packageName, Map<String, dynamic> options, String option) {
  final values = options[option];
  if (values == null) return const {};

  if (values is! Map<String, dynamic>) {
    throw new ArgumentError('Got `$values` for `$option` but expected a Map.');
  }
  final builderConfigs = values as Map<String, dynamic>;

  final parsedConfigs = <String, TargetBuilderConfig>{};
  for (final builderKey in builderConfigs.keys) {
    final builderConfig = _readMapOrThrow(builderConfigs, builderKey,
        _builderConfigOptions, 'builder config `$builderKey`',
        defaultValue: {});

    final isEnabled =
        _readBoolOrThrow(builderConfig, _enabled, defaultValue: true);

    final generateFor =
        _readInputSetOrThrow(builderConfig, _generateFor, allowNull: true);

    var parsedOptions = const BuilderOptions(const {});
    if (builderConfig.containsKey(_options)) {
      final options = builderConfig[_options];
      if (options is! Map) {
        throw new ArgumentError('Invalid builder options for `$builderKey`, '
            'got `$options` but expected a Map');
      }
      parsedOptions = new BuilderOptions(options as Map<String, dynamic>);
    }
    parsedConfigs[normalizeBuilderKeyUsage(builderKey, packageName)] =
        new TargetBuilderConfig(
      isEnabled: isEnabled,
      generateFor: generateFor,
      options: parsedOptions,
    );
  }
  return parsedConfigs;
}

List<String> _readListOfStringsOrThrow(
    Map<String, dynamic> options, String option,
    {Iterable<String> defaultValue,
    Iterable<String> validValues,
    bool allowNull: false}) {
  var value = options[option] ?? defaultValue?.toList();
  if (value == null && allowNull) return null;

  if (value is! List || (value as List).any((v) => v is! String)) {
    throw new ArgumentError(
        'Got `$value` for `$option` but expected a List<String>.');
  }
  if (validValues != null) {
    var invalidValues = (value as List).where((v) => !validValues.contains(v));
    if (invalidValues.isNotEmpty) {
      throw new ArgumentError('Got invalid values ``$invalidValues` for '
          '`$option`. Only `$validValues` are supported.');
    }
  }
  return new List<String>.from(value as List);
}

InputSet _readInputSetOrThrow(Map<String, dynamic> options, String option,
    {InputSet defaultValue, bool allowNull: false}) {
  final value = options[option];
  if (value == null && defaultValue != null) return defaultValue;
  if (value == null && allowNull) return null;

  if (value is List && value.every((v) => v is String)) {
    final include = new List<String>.from(value);
    return new InputSet(include: include);
  }

  if (value is Map) {
    final invalidOptions = value.keys.toList()
      ..removeWhere((k) => k == 'include' || k == 'exclude');
    if (invalidOptions.isNotEmpty) {
      throw new ArgumentError('Got invalid options `$invalidOptions` '
          'for $option. Only "include", and "exclude" are allowed');
    }
    final include = value.containsKey('include')
        ? new List<String>.from(value['include'] as List)
        : null;
    final exclude = value.containsKey('exclude')
        ? new List<String>.from(value['exclude'] as List)
        : null;
    return new InputSet(include: include, exclude: exclude);
  }
  throw new ArgumentError('Got `$value` for `$option` '
      'but expected a List<String> or a Map');
}
