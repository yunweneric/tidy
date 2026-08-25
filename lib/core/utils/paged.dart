/// One page of a list, and the page numbers that describe it.
///
/// Every table in the app does the same four lines of arithmetic to turn a
/// list and a page number into a slice — and gets the same two things wrong
/// when it does. The page has to be clamped, because the list it indexes
/// shrinks under it: a filter typed on page 12 of 15 leaves the page number
/// pointing past the end. And [totalPages] is at least one even when there is
/// nothing to show, because zero pages means the empty state has no page to
/// live on.
class Paged<T> {
  const Paged._({
    required this.items,
    required this.page,
    required this.totalPages,
    required this.totalItems,
  });

  /// Slices [items] for [page], counting from 1.
  factory Paged.of(List<T> items, {required int page, required int pageSize}) {
    assert(pageSize > 0, 'a page has to hold something');

    final totalPages = items.isEmpty ? 1 : (items.length / pageSize).ceil();
    final clamped = page.clamp(1, totalPages);
    final start = (clamped - 1) * pageSize;
    final end = (start + pageSize).clamp(0, items.length);

    return Paged._(
      items: items.isEmpty ? const [] : items.sublist(start, end),
      page: clamped,
      totalPages: totalPages,
      totalItems: items.length,
    );
  }

  /// The rows on this page.
  final List<T> items;

  /// The page actually being shown, which is not always the one asked for.
  final int page;

  /// Never below one.
  final int totalPages;

  /// The length of the whole list, for the "n shown" half of a footer.
  final int totalItems;
}
