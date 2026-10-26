/// The two Sonus Moments publishers (SN-45). They report the same verified
/// facts in different voices; no other publisher exists.
enum MomentPublisher {
  /// Polished, informative, factual.
  sonusDaily('Sonus Daily', '@sonusdaily'),

  /// Energetic and conversational, still exact.
  pulsePop('PulsePop', '@pulsepop');

  const MomentPublisher(this.label, this.handle);

  final String label;
  final String handle;
}
