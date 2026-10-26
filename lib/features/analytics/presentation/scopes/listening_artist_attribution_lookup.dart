import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../application/services/listening_artist_attribution.dart';

/// The app's artist attribution, or null where none is provided (plays
/// then count for their stored artist).
ListeningArtistAttribution? listeningArtistAttributionOf(BuildContext context) {
  try {
    return context.read<ListeningArtistAttribution?>();
  } on ProviderNotFoundException {
    return null;
  }
}
