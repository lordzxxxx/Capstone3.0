const assert = require('node:assert/strict');
const test = require('node:test');

const {
  assertStrongPassword,
  generateTemporaryPassword,
} = require('../functions/password_policy');

test('backend password policy accepts the shared strong-password shape', () => {
  assert.doesNotThrow(() => assertStrongPassword('Valid-QA-123!'));
  assert.throws(() => assertStrongPassword('short'));
  assert.throws(() => assertStrongPassword('alllowercase1!'));
  assert.throws(() => assertStrongPassword('ALLUPPERCASE1!'));
  assert.throws(() => assertStrongPassword('NoSymbol123'));
});

test('temporary account passwords are generated with the policy requirements', () => {
  const first = generateTemporaryPassword();
  const second = generateTemporaryPassword();
  assert.notEqual(first, second);
  assert.equal(first.length, 32);
  assert.doesNotThrow(() => assertStrongPassword(first));
  assert.doesNotThrow(() => assertStrongPassword(second));
});
