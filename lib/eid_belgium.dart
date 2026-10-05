/// Reads Belgian eID, Kids ID and residence cards through their contact chip.
///
/// A [BelgianEidReader] works over any `CardTransport` from the `eid`
/// package, such as a USB reader through `eid_ccid`. Reading needs no PIN.
library;

export 'package:eid/eid.dart';

export 'src/belgian_address.dart';
export 'src/belgian_card_authenticity.dart';
export 'src/belgian_card_info.dart';
export 'src/belgian_card_rejected.dart';
export 'src/belgian_certificates.dart';
export 'src/belgian_document_type.dart';
export 'src/belgian_eid_file.dart';
export 'src/belgian_eid_part.dart';
export 'src/belgian_eid_reader.dart';
export 'src/belgian_eid_watcher.dart';
export 'src/belgian_formatting.dart';
export 'src/belgian_identity.dart';
export 'src/belgian_language.dart';
export 'src/belgian_messages.dart';
export 'src/belgian_photo_cache.dart';
export 'src/belgian_root_certificates.dart';
export 'src/belgian_signature_verifier.dart';
export 'src/card_number.dart';
export 'src/national_number.dart';
export 'src/pin.dart' show PinCancelledException, PinException;
