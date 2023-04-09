// Copyright (C) 2023 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the EXAMPLES_LICENSE file.

import expect show *
import supabase
import .utils.client

TEST_TABLE ::= "test_table"

main:
  client := instantiate_client

  // TODO(florian): improve filters.
  client.rest.delete TEST_TABLE --filters=["id=gte.0"]

  row := client.rest.insert TEST_TABLE {
    "name": "test",
    "value": 11,
  }

  // A select over the table now contains the inserted row.
  rows := client.rest.select TEST_TABLE
  expect_not rows.is_empty

  row2 := client.rest.insert TEST_TABLE {
    "name": "test2",
    "value": 12,
  }

  rows = client.rest.select TEST_TABLE --filters=[
    "id=eq.$row2["id"]",
  ]
  expect_equals 1 rows.size

  // Update the row.
  client.rest.update TEST_TABLE --filters=[
    "id=eq.$row2["id"]",
  ] {
    "name": "test3",
  }

  // We can also use 'upsert' to update the row.
  client.rest.upsert TEST_TABLE {
    "id": row["id"],
    "name": "test4",
    "value": 13,
  }

  print (client.rest.select TEST_TABLE)
