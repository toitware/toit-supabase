// Copyright (C) 2023 Toitware ApS.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import encoding.url

import .supabase

/**
Provides ways to create $Filter objects for
  $PostgRest.select, $PostgRest.delete and $PostgRest.update
  operations.

Functions in this library create $Filter objects that can be used
  to filter the rows that are returned by the database.

Most of the functionality can be accessed through convenience functions,
  such as $equals, $less_than, or similar. More complex functionality
  might need direct calls to the $Filter constructors. Specifically,
  $Filter.raw allows to create any filter.

# Example
```
filters := [
  equals "id" 1,
  greater_than "age" 18,
  like "name" "John*",
  orr [
    andd [
      equals "city" "Copenhagen",
      equals "country" "Denmark",
    ],
    andd [
      equals "city" "Stockholm",
      equals "country" "Sweden",
    ],
  ],
]
```
*/

/**
Creates a filter for the 'equals' operation that tests whether
  the given $column is equal to the given $value.

Maps to the PostgreSQL `=` operator, and the PostgREST `eq` operator.

If the the $value or the column-value is null, then the result of the comparison is null.
Use $is_null or $iss to test for `null` values.
*/
equals column/string value/any -> Filter:
  return Filter.binary column Filter.EQ value

/**
Creates a filter for the 'not equals' operation that tests whether
  the given $column is not equal to the given $value.

Maps to the PostgreSQL `<>` operator, and the PostgREST `neq` operator.

If the $value or column-value is null, then the result of the comparison is null.
Use $is_null or $iss to test for `null` values.
*/
not_equals column/string value/any -> Filter:
  return Filter.binary column Filter.NEQ value

/**
Creates a filter for the 'greater than' operation that tests whether
  the given $column is greater than the given $value.

Maps to the PostgreSQL `>` operator, and the PostgREST `gt` operator.

If the $value or column-value is null, then the result of the comparison is null.
*/
greater_than column/string value/any -> Filter:
  return Filter.binary column Filter.GT value

/**
Creates a filter for the 'greater than or equal' operation that tests whether
  the given $column is greater than or equal to the given $value.

Maps to the PostgreSQL `>=` operator, and the PostgREST `gte` operator.

If the $value or column-value is null, then the result of the comparison is null.
*/
greater_than_or_equal column/string value/any -> Filter:
  return Filter.binary column Filter.GTE value

/**
Creates a filter for the 'less than' operation that tests whether
  the given $column is less than the given $value.

Maps to the PostgreSQL `<` operator, and the PostgREST `lt` operator.

If the $value or column-value is null, then the result of the comparison is null.
*/
less_than column/string value/any -> Filter:
  return Filter.binary column Filter.LT value

/**
Creates a filter for the 'less than or equal' operation that tests whether
  the given $column is less than or equal to the given $value.

Maps to the PostgreSQL `<=` operator, and the PostgREST `lte` operator.

If the $value or column-value is null, then the result of the comparison is null.
*/
less_than_or_equal column/string value/any -> Filter:
  return Filter.binary column Filter.LTE value

/**
Creates a filter for the 'like' operation that tests whether
  the given $column matches the given $pattern.

Maps to the PostgreSQL `LIKE` operator, and the PostgREST `like` operator.

Any '_' (underscore) in the $pattern matches any single character.
Any '%' or '*' (percent or asterisk) in the $pattern matches any sequence of zero
  or more characters.

If the $pattern or column-pattern is null, then the result of the comparison is null.

See $ilike for a case-insensitive version of this filter.
*/
like column/string pattern/string? -> Filter:
  return Filter.binary column Filter.LIKE pattern

/**
Variant of $like.

Matches in a case-insensitive manner.
*/
ilike column/string pattern/string? -> Filter:
  return Filter.binary column Filter.ILIKE pattern

/**
Creates a filter for the 'match' operation that tests whether
  the given $column matches the given $regex.

Maps to the PostgreSQL `~` operator, and the PostgREST `match` operator.

The $regex is a regular expression that is matched against the column-regex.

If the $regex or column-regex is null, then the result of the comparison is null.

See $imatch for a case-insensitive version of this filter.
See https://www.postgresql.org/docs/current/functions-matching.html#FUNCTIONS-POSIX-REGEXP for
  the syntax of the regular expressions.
*/
match column/string regex/string? -> Filter:
  return Filter.binary column Filter.MATCH regex

/**
Variant of $match.

Matches in a case-insensitive manner.
*/
imatch column/string regex/string? -> Filter:
  return Filter.binary column Filter.IMATCH regex

/**
Creates a filter for the 'in' operation that tests whether
  the given $column is one of the given $values.
*/
in column/string values/List -> Filter:
  return Filter.in column values

/**
Creates a filter for the 'is' operation that tests whether
  the given $column is the given $value.

Typically used to test for null or boolean values. For
  null, use $is_null instead.

The result of the comparison is always a boolean, even if
  the $value or column-value is null. This is especially
  important for the $nott filter, which will return null if
  its argument is null.

# Example

```
// Test whether the 'is_active' column is true.
// Always evaluates to a boolean, even if the column is null.
filter := iss "is_active" true
```
*/
iss column/string value/any -> Filter:
  return Filter.binary column Filter.IS value

/**
Variant of $iss.

Tests whether the given $column is not the given $value.
*/
is_distinct column/string value/any -> Filter:
  return Filter.binary column Filter.IS_DISTINCT value

/**
Creates a filter for the 'is' operation where the given $column is
  checked for null.

See $iss.
*/
is_null column/string -> Filter:
  return iss column null

/**
Creates a filter for the 'is' operation where the given $column is
  checked for not null.
*/
is_not_null column/string -> Filter:
  // We don't use `is_distinct` due to https://github.com/PostgREST/postgrest/issues/2879.
  return nott (is_null column)

/**
Creates a filter for the 'contains' operation that tests whether
  the array of the given $column contains all of the given $values.
*/
contains column/string values/List -> Filter:
  return Filter.array column Filter.CONTAINS values

/**
Creates a filter for the 'contained in' operation that tests whether
  the array of the given $column is contained in the given $values.
*/
contained_in column/string values/List -> Filter:
  return Filter.array column Filter.CONTAINED_IN values

/**
Creates a filter for the 'overlaps' operation that tests whether
  the array of the given $column overlaps with the given $values.
*/
overlaps column/string values/List -> Filter:
  return Filter.array column Filter.OVERLAPS values

/**
Creates a filter for the 'contains' operation that tests whether
  the range of the given $column contains the given $from and $to values.
*/
contains column/string from/any to/any -> Filter:
  return Filter.range column Filter.CONTAINS from to

/**
Creates a filter that requires all given $filters to be true.

The $filters list must not be empty.
*/
andd filters/List:
  return Filter.logical Filter.AND filters

/**
Creates a filter that requires any of the given $filters to be true.

The $filters list must not be empty.
*/
orr filters/List:
  return Filter.logical Filter.OR filters

/**
Inverts the given $filter.

If the result of the given $filter is null, then the result of the
  inverted filter is also null.
*/
nott filter/Filter -> Filter:
  return Filter.nott filter

/**
A PostgRest filter.

Can be used on $PostgRest.select, $PostgRest.update, and $PostgRest.delete.
*/
interface Filter:
  static EQ ::= "eq"
  static NEQ ::= "neq"
  static GT ::= "gt"
  static GTE ::= "gte"
  static LT ::= "lt"
  static LTE ::= "lte"
  static LIKE ::= "like"
  static ILIKE ::= "ilike"
  static MATCH ::= "match"
  static IMATCH ::= "imatch"
  static IS ::= "is"
  static IS_DISTINCT ::= "isdistinct"

  static IN ::= "in"

  static CONTAINS ::= "cs"
  static CONTAINED_IN ::= "cd"
  static OVERLAPS ::= "ov"
  static STRICTLY_LEFT ::= "sl"
  static STRICTLY_RIGHT ::= "sr"
  static NOT_EXTEND_RIGHT ::= "nxr"
  static NOT_EXTEND_LEFT ::= "nxl"
  static ADJACENT ::= "adj"

  static AND ::= "and"
  static OR ::= "or"

  static NOT ::= "not"

  /**
  Encodes the given $value.
  If $may_quote is true, then the value is quoted if necessary. This is
    only allowed for nested expressions, and not for the top-level filter.
    For example, `foo=eq.<some-value>` must not be quoted, but
    `or=(foo.eq.<some-value>)` may need to be quoted (and in this case
    quoting never hurts).
  */
  static encode value --may_quote/bool -> string:
    stringified := "$value"

    // It's not completely clear if float values with '.' must be quoted,
    // but in doubt we quote them.
    if may_quote and value is string:
      // See https://postgrest.org/en/stable/references/api/url_grammar.html#reserved-characters.
      // Values that contain ',', '.', ':', or '()' must be quoted.
      // In theory it's not necessary to quote values that only contain '"' or '\' (unless
      // it starts and ends the string), but that feels extremely wrong and dangerous.
      // Once a value is quoted any '\' or '"' must be escaped.
      needs_quoting := false
      for i := 0; i < stringified.size; i++:
        c := stringified[i]
        if c == ',' or c == '.' or c == ':' or c == '(' or c == ')' or c == '"' or c == '\\':
          needs_quoting = true
          break
      if needs_quoting:
        // Escape '\' and '"'.
        stringified = stringified.replace --all "\\" "\\\\"
        stringified = stringified.replace --all "\"" "\\\""
        stringified = "\"$stringified\""

    return url.encode stringified

  static encode_column column/string -> string:
    if column == "or" or column == "and":
      // A leading `or` or `and` would be confused with the logical operators.
      return "\"$column\""

    // Column names can be pretty much any string, so make sure we escape them
    // correctly.
    return encode column --may_quote


  /**
  Creates a binary filter.

  The operator must be one of the following:
    $EQ, $NEQ, $GT, $GTE, $LT, $LTE, $LIKE, $ILIKE, $MATCH, $IMATCH, $IS.

  See $equals, $not_equals, ... for documentation on each operator.
  */
  constructor.binary column/string op/string value/any:
    return FilterBinary_ column op value

  /**
  Creates an 'in' filter.

  See $in.
  */
  constructor.in column/string values/List:
    return FilterIn_ column values

  /**
  Creates an array filter.

  The operator must be one of the following:
    $CONTAINS, $CONTAINED_IN, $OVERLAPS.

  The given $values are encoded using `{...}` in the PostgREST request.
  */
  constructor.array column/string op/string values/List:
    return FilterArray_ column op values

  /**
  Creates a range filter.

  The operator must be one of the following:
    $CONTAINS, $CONTAINED_IN, $OVERLAPS.

  The $from and $to values must be either a number or a $Time.
  The range is encoded as `[from, to]` in the PostgREST request.
  */
  constructor.range column/string op/string from/any to/any:
    return FilterRange_ column op from to

  /**
  Creates a logical filter.

  The operator must be one of the following:
    $AND, $OR.

  See $andd and $orr.
  */
  constructor.logical op/string filters/List:
    return FilterLogical_ op filters

  /**
  Creates a 'not' filter.

  See $(nott filter).
  */
  constructor.nott filter/Filter:
    return FilterNot_ filter

  /**
  Creates a raw filter.

  The $raw string must be properly encoded and escaped. Use $encode to encode values.
  Similarly, some characters in column names must be escaped. Use $encode_column to
    encode column names.

  # Example:

  In this example we use the `any` and `all` modifiers to match any or all of the
    given patterns on a specific column (without repeating the column name). These
    modifiers are not directly supported and require the $Filter.raw
    constructor to be used.

  ```
  middle_patterns := [
    "Mid*",
    "*e",
  ]

  // Escape the patterns.
  // In this example this is not necessary, as no "dangerous" characters are used,
  // but it's good practice to always escape values that are not known to be safe.
  escaped_patterns := middle_patterns.map: Filter.encode it

  // Matches any row where the first name starts with 'O' or 'P', the middle name
  // matches all of the patterns in 'middle_patterns', and the last name starts
  // with 'O' and ends with 'n'.
  filters := [
    Filter.raw "first_name=like(any).{O*,P*}",
    Filter.raw "middle_name=like(all).{$(escaped_patterns.join ",")}",
    Filter.raw "last_name=like(all).{O*,*n}",
  ]
  ```
  */
  constructor.raw raw/string:
    return FilterRaw_ raw

  /**
  Builds the string representation of the filter that can be used in a PostgREST
    request.

  The result is already properly encoded and escaped.
  */
  to_string --nested/bool --negated/bool -> string

class FilterBinary_ implements Filter:
  column/string
  op/string
  value/any

  constructor .column .op .value:

  to_string --nested/bool --negated/bool -> string:
    not_string := negated ? "not." : ""
    column_string := Filter.encode_column column
    encoded_value := Filter.encode value --may_quote=nested
    return "$column_string$(nested ? "." : "=")$not_string$op.$encoded_value"

class FilterIn_ implements Filter:
  column/string
  values/List

  constructor .column .values:

  to_string --nested/bool --negated/bool -> string:
    not_string := negated ? "not." : ""
    column_string := Filter.encode_column column
    encoded_values := values.map: Filter.encode it --may_quote
    joined := encoded_values.join ","
    return "$column_string$(nested ? "." : "=")$not_string$Filter.IN.($joined)"


class FilterArray_ implements Filter:
  column/string
  op/string
  values/List

  constructor .column .op .values:

  to_string --nested/bool --negated/bool -> string:
    not_string := negated ? "not." : ""
    column_string := Filter.encode_column column
    encoded_values := values.map: Filter.encode it --may_quote
    joined := encoded_values.join ","
    return "$column_string$(nested ? "." : "=")$not_string$op.{$joined}"

class FilterRange_ implements Filter:
  column/string
  op/string
  from/any  // Can be a num, or a date.
  to/any    // Can be a num, or a date.

  constructor .column .op .from .to:
    if not (from is num and to is num) and not (from is Time and to is Time):
      throw "INVALID_ARGUMENT"

  to_string --nested/bool --negated/bool -> string:
    not_string := negated ? "not." : ""
    column_string := Filter.encode_column column
    encoded_from := Filter.encode from --may_quote
    encoded_to := Filter.encode to --may_quote
    return "$column_string$(nested ? "." : "=")$not_string$op.($encoded_from,$encoded_to)"

class FilterLogical_ implements Filter:
  op/string
  filters/List

  constructor .op .filters:

  to_string --nested/bool --negated/bool -> string:
    prefix_string/string := ?
    if negated and nested:
      prefix_string = "$(Filter.NOT).$op"
    else if negated and not nested:
      prefix_string = "$(Filter.NOT)=$op"
    else if not negated and nested:
      prefix_string = "$op"
    else:
      assert: not negated and not nested
      prefix_string = "$op="
    nested_strings := filters.map: it.to_string --nested --negated=false
    joined := nested_strings.join ","
    return "$prefix_string($joined)"

class FilterNot_ implements Filter:
  filter/Filter

  constructor .filter:

  to_string --nested/bool --negated/bool -> string:
    // The 'not' must be put in front of the operator. As such we
    // can't just prefix it to the stringified filter.
    return filter.to_string --nested=nested --negated=(not negated)

class FilterRaw_ implements Filter:
  raw/string

  constructor .raw:

  to_string --nested/bool --negated/bool -> string:
    if nested or negated:
      throw "RAW MUST NOT BE NESTED"
    return raw
