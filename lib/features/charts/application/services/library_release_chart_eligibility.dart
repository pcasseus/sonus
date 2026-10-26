import 'dart:developer' as developer;

import '../../../library/application/services/library_organization_service.dart';
import '../../domain/services/release_chart_eligibility.dart';

/// Release formats from the library: Singles never chart as releases, nor
/// do releases that might be Singles until their format is chosen.
/// Fails open: if formats can't be read, every release charts, as before.
class LibraryReleaseChartEligibility implements ReleaseChartEligibility {
  const LibraryReleaseChartEligibility(this._organization);

  final LibraryOrganizationService _organization;

  @override
  Future<Set<String>> excludedAlbumIds() async {
    try {
      return await _organization.releasesOffReleaseChart();
    } catch (error, stackTrace) {
      developer.log(
        'Release formats could not be read (${error.runtimeType})',
        name: 'sonus.charts',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
      return const {};
    }
  }
}
