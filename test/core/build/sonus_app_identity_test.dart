// App Update 1.2 device QA: the real app keeps its package and artwork
// provider; the QA flavor's are derived from its own package.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/build/sonus_app_identity.dart';
import 'package:sonus_next/features/player/application/services/media_session/artwork_content_uris.dart';

void main() {
  test('without a flavor (tests, prod) the package is the real app', () {
    expect(appFlavor, anyOf(isNull, 'prod'));
    expect(sonusApplicationId, 'com.sonus.sonus_next');
  });

  test('the artwork provider authority is the package plus .artwork', () {
    expect(ArtworkContentUris.authority, '$sonusApplicationId.artwork');
    expect(ArtworkContentUris.authority, 'com.sonus.sonus_next.artwork');
  });
}
