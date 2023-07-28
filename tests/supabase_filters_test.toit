// Copyright (C) 2023 Toitware ApS.

import supabase
import supabase.filter show *
import .supabase_local_server

import expect show *

main:
  config := get_supabase_config --sub_directory="supabase_test"

  client = supabase.Client --server_config=config
      --certificate_provider=: unreachable

  try:
    test_filters
  finally:
    client.close

TEST_TABLE ::= "filters"

client/supabase.Client := ?

test column/string expected filters/List:
  rows := client.rest.select TEST_TABLE --filters=filters
  expect_equals 1 rows.size
  expect_equals expected rows[0][column]

test_date column/string expected filters/List:
  rows := client.rest.select TEST_TABLE --filters=filters
  expect_equals 1 rows.size
  time_expected := Time.from_string expected
  time_actual := Time.from_string rows[0][column]
  expect_equals time_expected time_actual

test filters/List --count/int:
  rows := client.rest.select TEST_TABLE --filters=filters
  expect_equals count rows.size

test_filters:
  // The table should be empty now.
  rows := client.rest.select TEST_TABLE
  expect (not rows.is_empty)

  total_count := rows.size

  TEXT_ENTRIES := [
    "abc",
    "'",
    "\"",
    "\\",
    "\\\"",
    "\\\\",
    "\"\"",
    "foobar",
    "foo\"bar",
    "null",
  ]
  test --count=TEXT_ENTRIES.size [is_not_null "data"]

  TEXT_ENTRIES.do:
    test "data" it [equals "data" it]
    test "data" it [
      orr [
        equals "data" it,
        equals "data" "NOT IMPORTANT",
      ],
    ]
    test "data" it [
      orr [
        equals "data" "NOT IMPORTANT",
        equals "data" it,
      ],
    ]
    test --count=(TEXT_ENTRIES.size - 1) [
      not_equals "data" it,
    ]

    test "data" it [in "data" ["NOT ,IMPORTANT", it, "NOT IMPORTANT2"]]
    test --count=0 [in "data" ["NOT IMPORTANT", "NOT IMPORTANT2()"]]
    test --count=0 [in "data" []]

  4.repeat:
    pattern/string := ?
    if it == 0: pattern = "abc"
    else if it == 1: pattern = "a%"  // One ore more characters.
    else if it == 2: pattern = "a*"  // One or more characters.
    else: pattern = "ab_"  // Exactly one character.

    test "data" "abc" [like "data" pattern]
    test "data" "abc" [orr [like "data" pattern]]
    test --count=(TEXT_ENTRIES.size - 1) [orr [nott (like "data" pattern)]]

    pattern = pattern.to_ascii_upper
    test --count=0 [like "data" pattern]
    test "data" "abc" [ilike "data" pattern]

  test --count=0 [like "data" "a_"]
  test --count=0 [ilike "data" "a_"]

  test --count=2 [match "data" "f.*r"]
  test --count=0 [match "data" "F.*R"]
  test --count=2 [match "data" "oo.*r"]
  test --count=0 [match "data" "^oo.*r"]
  test --count=2 [imatch "data" "F.*R"]
  test --count=2 [imatch "data" "OO.*R"]
  test --count=0 [imatch "data" "^OO.*R"]
  test --count=0 [imatch "data" "^OO.*R"]

  INT_ENTRIES ::= [-1, 0, 1, 2, 3, 4, 5, 6, 7, 8]
  test --count=INT_ENTRIES.size [is_not_null "value"]

  INT_ENTRIES.do: | current/int |
    test "value" current [equals "value" current]
    test "value" current [
      orr [
        equals "value" current,
        equals "value" -99,
      ],
    ]
    test "value" current [
      orr [
        equals "value" -99,
        equals "value" current,
      ],
    ]
    test --count=(INT_ENTRIES.size - 1) [
      not_equals "value" current,
    ]

    test "value" current [in "value" [-99, current, -100]]
    test --count=0 [in "value" [-99, -100]]
    test --count=0 [in "value" []]

    strictly_less := (INT_ENTRIES.filter: it < current).size
    strictly_greater := (INT_ENTRIES.filter: it > current).size
    test --count=strictly_less [less_than "value" current]
    test --count=(strictly_less + 1) [less_than_or_equal "value" current]
    test --count=strictly_greater [greater_than "value" current]
    test --count=(strictly_greater + 1) [greater_than_or_equal "value" current]

  FLOAT_ENTRIES ::= [-1.1, 0.0, 1.1, 2.2, 3.3, 4.4, 5.5, 6.6, 7.7, 8.8]
  test --count=FLOAT_ENTRIES.size [is_not_null "valuef"]

  FLOAT_ENTRIES.do: | current/float |
    test "valuef" current [equals "valuef" current]
    test "valuef" current [
      orr [
        equals "valuef" current,
        equals "valuef" -99.9,
      ],
    ]
    test "valuef" current [
      orr [
        equals "valuef" -99.9,
        equals "valuef" current,
      ],
    ]
    test --count=(FLOAT_ENTRIES.size - 1) [
      not_equals "valuef" current,
    ]

    test "valuef" current [in "valuef" [-99.9, current, -100.0]]
    test --count=0 [in "valuef" [-99.9, -100.0]]

    strictly_less := (FLOAT_ENTRIES.filter: it < current).size
    strictly_greater := (FLOAT_ENTRIES.filter: it > current).size
    test --count=strictly_less [less_than "valuef" current]
    test --count=(strictly_less + 1) [less_than_or_equal "valuef" current]
    test --count=strictly_greater [greater_than "valuef" current]
    test --count=(strictly_greater + 1) [greater_than_or_equal "valuef" current]

  BOOL_ENTRIES ::= [true, false]
  test --count=BOOL_ENTRIES.size [is_not_null "b"]

  BOOL_ENTRIES.do: | current/bool |
    test "b" current [equals "b" current]
    test "b" current [iss "b" current]
    test "b" current [
      orr [
        equals "b" current,
        equals "b" current,
      ],
    ]
    test "b" current [
      orr [
        equals "b" current,
        equals "b" current,
      ],
    ]
    test --count=(BOOL_ENTRIES.size - 1) [
      not_equals "b" current,
    ]
    test --count=(total_count - 1) [
      nott (iss "b" current),
    ]

    test "b" current [in "b" [current, current, current]]
    test --count=0 [in "b" []]

  ARRAY_ENTRIES := [
    [1, 2, 3],
    [11, 22, 33, 44]
  ]
  test --count=ARRAY_ENTRIES.size [is_not_null "int_array"]

  ARRAY_ENTRIES.do: | array/List |
    rows = client.rest.select TEST_TABLE --filters=[
      contains "int_array" array,
    ]
    expect_equals 1 rows.size
    expect_equals array rows[0]["int_array"]

    rows = client.rest.select TEST_TABLE --filters=[
      contains "int_array" array[0..1],
    ]
    expect_equals 1 rows.size
    expect_equals array rows[0]["int_array"]

    rows = client.rest.select TEST_TABLE --filters=[
      contains "int_array" array[0..2],
    ]
    expect_equals 1 rows.size
    expect_equals array rows[0]["int_array"]

    rows = client.rest.select TEST_TABLE --filters=[
      contains "int_array" array[2..],
    ]
    expect_equals 1 rows.size
    expect_equals array rows[0]["int_array"]

    rows = client.rest.select TEST_TABLE --filters=[
      contains "int_array" array + [99],
    ]
    expect rows.is_empty

    rows = client.rest.select TEST_TABLE --filters=[
      contains "int_array" [99],
    ]
    expect rows.is_empty

    rows = client.rest.select TEST_TABLE --filters=[
      contained_in "int_array" array,
    ]
    expect_equals 1 rows.size
    expect_equals array rows[0]["int_array"]

    rows = client.rest.select TEST_TABLE --filters=[
      contained_in "int_array" array[0..1],
    ]
    expect rows.is_empty

    rows = client.rest.select TEST_TABLE --filters=[
      contained_in "int_array" array[1..],
    ]
    expect rows.is_empty

    rows = client.rest.select TEST_TABLE --filters=[
      contained_in "int_array" array + [99],
    ]
    expect_equals 1 rows.size
    expect_equals array rows[0]["int_array"]

    rows = client.rest.select TEST_TABLE --filters=[
      overlaps "int_array" array,
    ]
    expect_equals 1 rows.size
    expect_equals array rows[0]["int_array"]

    rows = client.rest.select TEST_TABLE --filters=[
      overlaps "int_array" array[0..1],
    ]
    expect_equals 1 rows.size
    expect_equals array rows[0]["int_array"]

    rows = client.rest.select TEST_TABLE --filters=[
      overlaps "int_array" array + [99]
    ]
    expect_equals 1 rows.size
    expect_equals array rows[0]["int_array"]

    rows = client.rest.select TEST_TABLE --filters=[
      overlaps "int_array" array[1..] + [99]
    ]
    expect_equals 1 rows.size
    expect_equals array rows[0]["int_array"]

  // TODO(florian): add range functions and tests.

  DATES_ENTRY ::= [
    "2023-07-27T13:37:21.000000+00:00",
    "1997-05-02T19:12:34.567891+00:00"
  ]
  test --count=DATES_ENTRY.size [is_not_null "dates"]

  DATES_ENTRY.do: | date/string |
    test_date "dates" date [equals "dates" date]
    test_date "dates" date [
      orr [
        equals "dates" date,
        equals "dates" "1970-01-01T00:00:00Z",
      ],
    ]
    test_date "dates" date [
      orr [
        equals "dates" "1970-01-01T00:00:00Z",
        equals "dates" date,
      ],
    ]
    test --count=(DATES_ENTRY.size - 1) [
      not_equals "dates" date,
    ]

    test_date "dates" date [in "dates" [date, date, date]]
    test --count=0 [in "dates" []]

    strictly_less := (DATES_ENTRY.filter: it < date).size
    strictly_greater := (DATES_ENTRY.filter: it > date).size
    test --count=strictly_less [less_than "dates" date]
    test --count=(strictly_less + 1) [less_than_or_equal "dates" date]
    test --count=strictly_greater [greater_than "dates" date]
    test --count=(strictly_greater + 1) [greater_than_or_equal "dates" date]

  // Test logical and 'not' operators.
  rows = client.rest.select TEST_TABLE --filters=[
    andd [
      greater_than "value" 5,
      less_than "value" 7,
    ],
  ]
  expect_equals 1 rows.size
  expect_equals 6 rows[0]["value"]

  rows = client.rest.select TEST_TABLE --filters=[
    andd [
      nott (greater_than "value" 6),
      nott (less_than "value" 6),
    ],
  ]
  expect_equals 1 rows.size
  expect_equals 6 rows[0]["value"]

  rows = client.rest.select TEST_TABLE --filters=[
    andd [
      orr [
        greater_than "value" 5,
        greater_than "value" 6,
      ],
      orr [
        less_than "value" 6,
        less_than "value" 7,
      ],
    ],
  ]
  expect_equals 1 rows.size
  expect_equals 6 rows[0]["value"]

  rows = client.rest.select TEST_TABLE --filters=[
    nott (nott (nott (nott (equals "value" 6)))),
  ]
  expect_equals 1 rows.size
  expect_equals 6 rows[0]["value"]

  rows = client.rest.select TEST_TABLE --filters=[
    orr [
      nott
        orr [
          nott (equals "value" 6),
        ],
    ],
  ]
  expect_equals 1 rows.size
  expect_equals 6 rows[0]["value"]
