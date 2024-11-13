// Copyright (C) 2023 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the EXAMPLES_LICENSE file.

import expect show *
import supabase
import .utils.client

TEST-TABLE ::= "test_table"

main:
  client := instantiate-client

  // TODO(florian): improve filters.
  client.rest.delete TEST-TABLE --filters=["id=gte.0"]

  row := client.rest.insert TEST-TABLE {
    "name": "test",
    "value": 11,
  }

  // A select over the table now contains the inserted row.
  rows := client.rest.select TEST-TABLE
  expect-not rows.is-empty

  row2 := client.rest.insert TEST-TABLE {
    "name": "test2",
    "value": 12,
  }

  rows = client.rest.select TEST-TABLE --filters=[
    "id=eq.$row2["id"]",
  ]
  expect-equals 1 rows.size

  // Update the row.
  client.rest.update TEST-TABLE --filters=[
    "id=eq.$row2["id"]",
  ] {
    "name": "test3",
  }

  // We can also use 'upsert' to update the row.
  client.rest.upsert TEST-TABLE {
    "id": row["id"],
    "name": "test4",
    "value": 13,
  }

  print (client.rest.select TEST-TABLE)
