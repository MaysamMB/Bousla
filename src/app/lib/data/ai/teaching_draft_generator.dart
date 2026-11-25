/// Instructor-only AI draft service. The caller validates the model response.
abstract interface class TeachingDraftGenerator {
  Future<String> generate(String prompt);
}
