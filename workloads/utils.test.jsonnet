local utils = import 'utils.libsonnet';

local test(name, actual, expected) =
  if actual != expected then
    error 'Test failed! ' + name + '\n  Actual: ' + actual + '\n  Expected: ' + expected
  else
    null;

local testSuite(config) =
  local results = std.prune([
    if config[x].actual == config[x].expect then
      null
    else
      { name: x } + config[x]
    for x in std.objectFields(config)
  ]);
  if results == [] then
    std.length(config) + ' tests passed'
  else
    local format(arr, acc=[]) =
      if arr == [] then
        acc
      else
        local result = '\tTest failed: ' + arr[0].name + '\n\t\tActual: ' + arr[0].actual + '\n\t\tExpected: ' + arr[0].expect;
        format(arr[1:], acc + [result]);
    error std.length(results) + ' tests failed.\n\n' + std.join('\n', format(results));

local cm = utils.config_map({
  apiVersion: 'v1',
  kind: 'ConfigMap',
  metadata: {
    name: 'seafile-config',
    namespace: 'admin',
  },
  data: { DEBUG: 'true' },
});
local cm2 = utils.config_map({
  apiVersion: 'v1',
  kind: 'ConfigMap',
  metadata: { name: 'seafile-config' },
  data: { DEBUG: 'false' },
});

testSuite({
  'no substitutions': {
    actual: utils.varSubstitute('the happy fox', { animal: 'hound' }),
    expect: 'the happy fox',
  },
  'escaping $': {
    actual: utils.varSubstitute('the $${money} fox', { animal: 'hound' }),
    expect: 'the ${money} fox',
  },
  'extra $': {
    actual: utils.varSubstitute('the $money fox', { animal: 'hound' }),
    expect: 'the $money fox',
  },
  substitution: {
    actual: utils.varSubstitute('the happy ${animal}!', { animal: 'hound' }),
    expect: 'the happy hound!',
  },
  'back-to-back': {
    actual: utils.varSubstitute('${animal}${animal}$$${animal}', { animal: 'hound' }),
    expect: 'houndhound$hound',
  },
  recursive: {
    actual: utils.varSubstitute('the happy ${animal}', { animal: '${animal}' }),
    expect: 'the happy ${animal}',
  },
  'config_map: stable name (no hash suffix)': {
    actual: cm.metadata.name,
    expect: 'seafile-config',
  },
  'config_map: immutable absent': {
    actual: std.toString(std.objectHas(cm, 'immutable')),
    expect: 'false',
  },
  'config_map: namespace preserved': {
    actual: cm.metadata.namespace,
    expect: 'admin',
  },
  'config_map: kind preserved': {
    actual: cm.kind,
    expect: 'ConfigMap',
  },
  'config_map: hash not serialized into manifest': {
    actual: std.toString(
      std.length(std.findSubstr(std.manifestJson(cm), 'config_hash')) == 0
      && std.length(std.findSubstr(std.manifestJson(cm), 'configmap-hash')) == 0
    ),
    expect: 'true',
  },
  'config_map: hidden config_hash is a 32-char md5': {
    actual: std.toString(std.length(cm.config_hash) == 32),
    expect: 'true',
  },
  'config_map: hash changes when data changes': {
    actual: std.toString(cm.config_hash != cm2.config_hash),
    expect: 'true',
  },
})
