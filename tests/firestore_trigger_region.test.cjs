const assert = require('node:assert/strict');

const {
  FIRESTORE_DATABASE_ID,
  FIRESTORE_TRIGGER_REGION,
} = require('../functions/firestore_trigger_config');

assert.equal(FIRESTORE_DATABASE_ID, 'capstone-c98f9');
assert.equal(
    FIRESTORE_TRIGGER_REGION,
    'asia-east1',
    'Firestore Eventarc triggers must be colocated with the live database.',
);
