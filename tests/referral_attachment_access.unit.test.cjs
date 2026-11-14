const assert = require('node:assert/strict');

const {
  attachmentAccessAllowed,
  attachmentIsDeclared,
  parseReferralAttachmentPath,
} = require('../functions/referral_attachment_access');

describe('referral attachment server authorization', () => {
  const referral = {assignedDoctorUid: 'doctor-1'};

  it('accepts a valid owner/referral/file path', () => {
    assert.deepEqual(
        parseReferralAttachmentPath(
            'referral_attachments/bhw-1/referral-1/171234_file.pdf'),
        {
          ownerUid: 'bhw-1',
          referralId: 'referral-1',
          fileName: '171234_file.pdf',
        },
    );
  });

  it('rejects path traversal and invalid file names', () => {
    assert.equal(
        parseReferralAttachmentPath(
            'referral_attachments/bhw-1/referral-1/../private.pdf'),
        null,
    );
    assert.equal(
        parseReferralAttachmentPath(
            'referral_attachments/bhw-1/referral-1/file name.pdf'),
        null,
    );
  });

  it('requires the attachment to be declared on the referral', () => {
    const path = 'referral_attachments/bhw-1/referral-1/file.pdf';
    assert.equal(attachmentIsDeclared([{storagePath: path}], path), true);
    assert.equal(attachmentIsDeclared([], path), false);
    assert.equal(attachmentIsDeclared([{storagePath: 'other'}], path), false);
  });

  it('allows only an approved active assigned doctor', () => {
    const doctor = {
      role: 'DOCTOR',
      approvalStatus: 'approved',
      accountStatus: 'active',
    };
    assert.equal(attachmentAccessAllowed(doctor, 'doctor-1', referral), true);
    assert.equal(attachmentAccessAllowed(doctor, 'doctor-2', referral), false);
    assert.equal(
        attachmentAccessAllowed(
            {...doctor, accountStatus: 'archived'},
            'doctor-1',
            referral,
        ),
        false,
    );
  });

  it('allows CHO access only with the referral-view permission', () => {
    const cho = {
      role: 'CHO',
      approvalStatus: 'approved',
      accountStatus: 'active',
      permissions: ['referrals.view'],
    };
    assert.equal(attachmentAccessAllowed(cho, 'cho-1', referral), true);
    assert.equal(
        attachmentAccessAllowed(
            {...cho, permissions: ['patients.view']},
            'cho-1',
            referral,
        ),
        false,
    );
  });
});
