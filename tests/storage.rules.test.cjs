const fs = require('node:fs');
const path = require('node:path');
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require('@firebase/rules-unit-testing');

const projectId = 'demo-capstone-security';
let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId,
    storage: {
      rules: fs.readFileSync(
        path.resolve(__dirname, '..', 'storage.rules'),
        'utf8',
      ),
    },
  });
});

beforeEach(async () => testEnv.clearStorage());
after(async () => {
  if (testEnv) await testEnv.cleanup();
});

function storageFor(uid, token = {}) {
  return testEnv.authenticatedContext(uid, token).storage();
}

describe('barangay branding storage boundaries', () => {
  it('allows CHO Admin image uploads and rejects non-image content', async () => {
    const adminStorage = storageFor('admin-1', {role: 'CHO_ADMIN'});
    const valid = adminStorage
      .ref('barangay-branding/BARANGAY_10/logo-1.png')
      .put(Buffer.from('test image'), {contentType: 'image/png'});
    await assertSucceeds(valid);

    const invalid = adminStorage
      .ref('barangay-branding/BARANGAY_10/logo-2.txt')
      .put(Buffer.from('not an image'), {contentType: 'text/plain'});
    await assertFails(invalid);
  });

  it('rejects branding uploads from normal CHO users and unauthenticated users', async () => {
    const normalChoStorage = storageFor('cho-1', {role: 'CHO'});
    await assertFails(
      normalChoStorage
        .ref('barangay-branding/BARANGAY_10/logo.png')
        .put(Buffer.from('test image'), {contentType: 'image/png'}),
    );

    const publicStorage = testEnv.unauthenticatedContext().storage();
    await assertFails(
      publicStorage
        .ref('barangay-branding/BARANGAY_10/logo.png')
        .put(Buffer.from('test image'), {contentType: 'image/png'}),
    );
  });

  it('keeps uploaded branding files immutable', async () => {
    const ref = storageFor('admin-1', {role: 'CHO_ADMIN'})
      .ref('barangay-branding/BARANGAY_10/logo.png');
    await assertSucceeds(
      ref.put(Buffer.from('test image'), {contentType: 'image/png'}),
    );
    await assertFails(
      ref.put(Buffer.from('replacement'), {contentType: 'image/png'}),
    );
  });

  it('keeps referral attachments immutable after an owner upload', async () => {
    const ref = storageFor('bhw-1')
      .ref('referral_attachments/bhw-1/referral-1/attachment.png');
    await assertSucceeds(
      ref.put(Buffer.from('test image'), {contentType: 'image/png'}),
    );
    await assertFails(
      ref.put(Buffer.from('replacement'), {contentType: 'image/png'}),
    );
  });
});
