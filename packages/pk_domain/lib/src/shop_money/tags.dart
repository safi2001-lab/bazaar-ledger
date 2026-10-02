/// What the ledger's one free dimension carries, and who owns each prefix.
///
/// `journal_lines.cost_centre` is a free text column the schema has carried
/// since v1 and nothing used until M48. It is now shared, so every tag is a
/// prefix and a colon, and a feature reads only its own prefix:
///
///   `loan:<account id>`          M48. Every line of every entry a loan
///                                writes, so a month of interest only (it
///                                never touches the loan's own account)
///                                still lands on the loan's statement.
///   `expense:recurring:<id>`     M47. Every line of an expense paid against
///                                a monthly bill, so "has this month's rent
///                                gone?" is a lookup and not a guess by
///                                amount.
///   `income:<head key>`          M47. Every line of the shop's other income,
///                                the head it came under (rent from a
///                                sub-let, commission, scrap...). The books
///                                keep one Other Income account, which the
///                                profit and loss already reads; the head
///                                is this tag.
///
/// A tag marks the entry that put something on the books. A cancellation
/// (M31) mirrors the entry without it, and is found by the document's
/// status, as every cancelled document is: a report that sums a tag reads
/// standing documents, never the tag alone.
library;

/// The prefix every expense tag starts with.
const expenseTagPrefix = 'expense:';

/// The prefix every other-income tag starts with.
const incomeTagPrefix = 'income:';

/// The tag on an expense paid against the monthly bill [templateId].
String recurringTag(String templateId) =>
    '${expenseTagPrefix}recurring:$templateId';

/// The tag on other income that came under [headKey].
String incomeTag(String headKey) => '$incomeTagPrefix$headKey';

/// The head an `income:` tag names, or null when [tag] is not one.
String? incomeHeadOfTag(String? tag) =>
    tag != null && tag.startsWith(incomeTagPrefix)
    ? tag.substring(incomeTagPrefix.length)
    : null;
