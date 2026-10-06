# eid_belgium

[![Video tour](https://img.shields.io/badge/Video-Guided_tour-c4302b?logo=youtube&logoColor=white)](https://www.youtube.com/watch?v=oH_-1EU7DNc)
[![Live demo](https://img.shields.io/badge/Live_demo-packages.comapps.be-b7791f)](https://packages.comapps.be/eid_belgium/)
[![Pub Version](https://img.shields.io/pub/v/eid_belgium?color=0175C2)](https://pub.dev/packages/eid_belgium)
[![Build](https://img.shields.io/github/actions/workflow/status/raphrmx/eid_belgium/ci.yml?branch=main&label=build)](https://github.com/raphrmx/eid_belgium/actions/workflows/ci.yml)
![Maintainer](https://img.shields.io/badge/Maintainer-Raphael_Vrient-733d90)
[![Licence](https://img.shields.io/badge/Licence-MIT-8C6A3F)](LICENSE)
![Platforms](https://img.shields.io/badge/Platforms-Android,_iOS,_macOS,_Windows,_Linux,_Web-22375C.svg)
[![Donate with PayPal](https://img.shields.io/badge/Donate-PayPal-00457C?logo=paypal&logoColor=white)](https://www.paypal.com/donate/?hosted_button_id=ZN6D382YQAV5N)

Reads the Belgian eID, the Kids ID and the residence cards (EU, EU+, A to N)
through their contact chip: identity, address, photo and certificates. None
of it needs the PIN.

## Install

```yaml
dependencies:
  eid_belgium: ^0.1.0
  eid_ccid: ^0.1.0 # a USB card reader, in a Flutter application
```

## Read a card

```dart
import 'package:eid_belgium/eid_belgium.dart';
import 'package:eid_ccid/eid_ccid.dart';

final readers = await CcidTransport.listReaders();
final transport = await CcidTransport.connect(readers.first);

final eid = await BelgianEidReader(transport).read();
eid.identity.lastName;        // Dupont
eid.identity.birthDate;       // 1985-07-30
eid.address?.municipality;    // Bruxelles
eid.photo;                    // a JPEG

await transport.disconnect();
```

## Read on insertion

```dart
final watcher = BelgianEidWatcher(
  CcidTerminal.any(),        // every reader, those plugged in later included
  autoRead: true,            // read as soon as the card is in
  parts: BelgianEidPart.all, // address, photo, signatures, nationalNumber
  acceptExpired: false,      // turn down expired cards
  acceptedTypes: null,       // every document type
  pinPrompt: null,           // ask for the PIN before reading
  rememberPhotos: true,      // skip the photo of a card read again
  verifySignatures: true,    // check the national register's signatures
  verifyCard: true,          // have the chip prove it is genuine
  trustedRoots: null,        // the Belgian roots
  showPrivateData: false,    // the national register number, see Personal data
  onProgress: null,          // 0 to 1, for a progress bar
  onApdu: null,              // every command and answer, never the PIN
)..start();

watcher.events.listen((event) {
  switch (event) {
    case BelgianCardRead read:
      show(read.eid);
    case BelgianCardReadFailed failed:
      showError(failed.error);
    case BelgianCardRemoved _:
      clear();
    case BelgianCardInserted _ || BelgianPinVerified _:
      break;
  }
});
```

Every option can be changed at any time. `parts`, `acceptExpired`,
`acceptedTypes`, `verifySignatures`, `verifyCard`, `trustedRoots` and
`onProgress` also exist on `BelgianEidReader.read`.

## Read less

```dart
final eid = await reader.read(parts: {BelgianEidPart.address});
eid.photo;                    // null
eid.identity.nationalNumber;  // null, and removed from the raw fields too
```

## Turn cards down

Three checks are on by default: an expired card, a card whose signatures do
not hold and a cloned chip are turned down. `acceptedTypes` adds a fourth:

```dart
await reader.read(acceptedTypes: {BelgianDocumentType.eid});
```

A card turned down throws a `BelgianCardRejectedException` whose `reason` is
`expired`, `documentType`, `signature` or `notGenuine`.

- `verifySignatures` checks the national register's signatures of the
  identity, address and photo, and its certificate against the Belgian roots
  the package holds (`belgianRootCertificates`).
- `verifyCard` has the chip sign a random challenge with its own key, which a
  copy of the files cannot do. It needs `verifySignatures`. Cards older than
  applet 1.8 cannot prove it: `eid.authenticity` is then `notSupported`.
  Each proof spends one of the 5000 the chip allows before it wants the PIN
  once.

On the web, the signatures are checked by the browser's WebCrypto.
`BelgianSignatureVerifier` makes the same checks away from the card, on a
server for instance, from `eid.toJson()`.

## PIN

```dart
final watcher = BelgianEidWatcher(
  terminal,
  // triesLeft is null the first time. Return null if the holder gives up.
  pinPrompt: (triesLeft) => showMyPinDialog(triesLeft),
)..start();

await reader.verifyPin('1234');   // PinException: e.triesLeft, e.isBlocked
await reader.pinTriesLeft();      // without spending a try
await reader.changePin('1234', '5678');
```

Three wrong PINs in a row block the card. A PIN that is not 4 to 12 digits
never reaches the card.

## Certificates

```dart
final certificates = await reader.readCertificates();
certificates.authentication?.subject.commonName; // Alice Specimen (Authentication)
await certificates.verify(BelgianSignatureVerifier()); // {} when all chain up
```

Revocation is not checked.

## Helpers

```dart
identity.age;                       // null when the birth date is partial
identity.isAdult;                   // certainly 18 or older
identity.isExpired;
formatBelgianNationalNumber(number, masked: true); // 85.07.30-***.**
formatBelgianCardNumber(identity.cardNumber);      // 592-1234567-89
BelgianDocumentType.eid.label(BelgianLanguage.nl); // Identiteitskaart
identity.fullName;                                 // Alice Marie Specimen
address.lines;                     // [Rue de la Loi 16, 1000 Bruxelles]
formatBelgianDate(identity.validUntil, BelgianLanguage.de); // 13. März 2034
identity.sex.label(BelgianLanguage.fr);            // Féminin
belgianErrorMessage(failed.error, BelgianLanguage.fr); // Carte expirée le ...
```

`belgianErrorMessage` turns any error of a read into a sentence for the
holder, in French, Dutch, German or English.

Text is as the card holds it, in the language of the issuing municipality.

## Without a reader

```dart
import 'package:eid_belgium/testing.dart';

final card = SimulatedBelgianCard(lastName: 'Peeters', pin: '4321');
final eid = await BelgianEidReader(card).read();
card.remove();
card.insert();
```

A made-up national register signs it, whose root is trusted for the simulator
alone. `tamperedLastName` and `cloned` give cards the checks turn down.

## Personal data

The holder must consent to their card being read, and only those authorised
may use the national register number.

The number is therefore read only when asked for twice:
`BelgianEidPart.nationalNumber` in `parts`, which `BelgianEidPart.all`
includes, and `showPrivateData`, off by default. Most uses do not need it.

```dart
await reader.read();                        // identity.nationalNumber is null
await reader.read(showPrivateData: true);   // and here it is
await reader.read(
  parts: {BelgianEidPart.address},          // no nationalNumber part:
  showPrivateData: true,                    // still null
);
```

Without it, the number is removed from the identity file once read, and
the signatures are checked but not returned: they would give it away.
`onApdu` gets the answers that hold it with their data zeroed.

## Sources

The documents published with the Belgian middleware,
[Fedict/eid-mw](https://github.com/Fedict/eid-mw): card content v5.4, ID and
address file contents v5.0, Belpic V1.8 reference manual.

## License

Released under the [MIT licence](https://pub.dev/packages/eid_belgium/license).

## More from COMAPPS

Electronic identity cards in Dart:

| Package | What it does |
| --- | --- |
| [eid](https://pub.dev/packages/eid) | APDUs, ISO 7816-4 file reading and the values national cards share. |
| [eid_ccid](https://pub.dev/packages/eid_ccid) | The transport for a USB or PC/SC card reader. |

Every package COMAPPS publishes is listed at
[packages.comapps.be](https://packages.comapps.be).
