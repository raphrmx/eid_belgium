## 0.1.1

- `showPrivateData`, off by default, on `BelgianEidReader.read`,
  `readIdentity` and `BelgianEidWatcher`. The national register number,
  whose use Belgian law restricts, now needs both
  `BelgianEidPart.nationalNumber` in `parts` and `showPrivateData`: reads
  leave it out by default.

## 0.1.0

- First release: reads the Belgian eID, Kids ID and residence cards through
  their contact chip, over any `eid` transport.
- `BelgianEidWatcher` reads each card as it goes in (`autoRead`).
- Options: `parts`, `acceptExpired`, `acceptedTypes`, `pinPrompt`,
  `rememberPhotos`, `verifySignatures`, `verifyCard`, `onApdu`, `onProgress`.
- Checks, on by default: national register signatures and photo hash,
  genuine chip, expiry. Certificate chains up to the Belgian roots. On the
  web, signatures are checked with WebCrypto.
- PIN: `verifyPin`, `pinTriesLeft`, `changePin`.
- Helpers: age, expiry, number formatting, `toJson` and `fromJson`.
- In French, Dutch, German and English: error messages, dates, sex and
  document type labels.
- `SimulatedBelgianCard` stands in for a card and a reader.
