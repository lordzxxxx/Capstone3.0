const crypto = require('crypto');

const MINIMUM_PASSWORD_LENGTH = 8;
const MAXIMUM_PASSWORD_LENGTH = 128;

function passwordPolicyFailures(password) {
  const value = typeof password === 'string' ? password : '';
  const failures = [];
  if (value.length < MINIMUM_PASSWORD_LENGTH) {
    failures.push(`at least ${MINIMUM_PASSWORD_LENGTH} characters`);
  }
  if (value.length > MAXIMUM_PASSWORD_LENGTH) {
    failures.push(`no more than ${MAXIMUM_PASSWORD_LENGTH} characters`);
  }
  if (!/[A-Z]/.test(value)) failures.push('an uppercase letter');
  if (!/[a-z]/.test(value)) failures.push('a lowercase letter');
  if (!/[0-9]/.test(value)) failures.push('a number');
  if (!/[^A-Za-z0-9]/.test(value)) failures.push('a special character');
  return failures;
}

function assertStrongPassword(password) {
  const failures = passwordPolicyFailures(password);
  if (failures.length > 0) {
    throw new Error(`Password must contain ${failures.join(', ')}.`);
  }
}

function generateTemporaryPassword() {
  const parts = [
    'ABCDEFGHJKLMNPQRSTUVWXYZ'[crypto.randomInt(24)],
    'abcdefghijkmnopqrstuvwxyz'[crypto.randomInt(24)],
    '23456789'[crypto.randomInt(8)],
    '!@#$%^&*_-+='[crypto.randomInt(12)],
  ];
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#$%^&*_-+=';
  while (parts.length < 32) {
    parts.push(alphabet[crypto.randomInt(alphabet.length)]);
  }
  for (let index = parts.length - 1; index > 0; index -= 1) {
    const swapIndex = crypto.randomInt(index + 1);
    [parts[index], parts[swapIndex]] = [parts[swapIndex], parts[index]];
  }
  return parts.join('');
}

module.exports = {
  MINIMUM_PASSWORD_LENGTH,
  MAXIMUM_PASSWORD_LENGTH,
  assertStrongPassword,
  generateTemporaryPassword,
  passwordPolicyFailures,
};
