## 0.1.2

- Needs eid 0.1.1 and crypto 3.0.7.
- The README says what reading a card takes: a USB card reader, through
  `eid_ccid`. On the web, where no page reaches a card reader, the package
  checks cards read elsewhere and runs the simulator. The platform badge no
  longer lists the web.
- The README opens on a picture of which packages to add for each document,
  and lists eid_icao and eid_nfc among the other eid packages. pub.dev shows
  the same picture as a screenshot.

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
