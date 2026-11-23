// Firestore Eventarc triggers must run in the same region as the named
// Firestore database. `capstone-c98f9` is provisioned in asia-east1.
// Callable HTTPS functions intentionally remain in us-central1 for backwards
// compatible client URLs.
const FIRESTORE_DATABASE_ID = 'capstone-c98f9';
const FIRESTORE_TRIGGER_REGION = 'asia-east1';

module.exports = {
  FIRESTORE_DATABASE_ID,
  FIRESTORE_TRIGGER_REGION,
};
