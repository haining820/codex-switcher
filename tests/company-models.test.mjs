import { test } from 'node:test';
import assert from 'node:assert/strict';
import { normalizeModels, orderModels, selectionIndex } from '../launcher/company-models.mjs';

test('模型去重和控制字符过滤', () => {
  const models = normalizeModels({ data: [
    { id: 'model-one', tag_list: ['default\n'] },
    { id: 'model-one' },
    { id: 'bad\nmodel' },
    { id: 'model-two' },
  ] });
  assert.deepEqual(models.map(model => model.id), ['model-one', 'model-two']);
  assert.deepEqual(models[0].tags, ['default']);
  assert.throws(() => normalizeModels({ data: [] }));
});

test('默认项优先保留上次有效选择', () => {
  const models = [{ id: 'gpt-example' }, { id: 'company-example' }];
  assert.equal(orderModels(models, 'company-example')[0].id, 'company-example');
  assert.equal(orderModels(models, 'removed')[0].id, 'gpt-example');
});

test('编号和回车选择边界', () => {
  assert.equal(selectionIndex('', 3), 0);
  assert.equal(selectionIndex('3', 3), 2);
  for (const input of ['0', '-1', '4', '1.5', 'abc', '99999999999999999999']) {
    assert.equal(selectionIndex(input, 3), -1);
  }
});
