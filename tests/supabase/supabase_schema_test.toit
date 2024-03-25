// Copyright (C) 2023 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the TESTS_LICENSE file.

import supabase
import supabase.filter
import .supabase_local_server

import expect show *

main:
  config := get_supabase_config --sub_directory="supabase/supabase_test"

  client = supabase.Client --server_config=config
      --certificate_provider=: unreachable

  try:
    test_schema
  finally:
    client.close

TEST_SCHEMA ::= "other_schema"
TEST_TABLE ::= "some_table"

client/supabase.Client := ?

test_schema:
  client.rest.delete TEST_TABLE
      --schema=TEST_SCHEMA
      --filters=[
        // Delete requires a where clause.
        filter.greater-than-or-equal "id" 0,
      ]

  inserted := client.rest.insert TEST_TABLE
      --schema=TEST_SCHEMA
      { "value": 499 }

  expect-equals 499 inserted["value"]

  rows := client.rest.select TEST_TABLE --schema=TEST_SCHEMA
  expect-equals 1 rows.size
  expect-equals 499 rows[0]["value"]

  client.rest.update TEST_TABLE
      --schema=TEST_SCHEMA
      --filters=[
        filter.equals "id" rows[0]["id"],
      ]
      { "value": 500 }
  rows = client.rest.select TEST_TABLE --schema=TEST_SCHEMA
  expect-equals 1 rows.size
  expect-equals 500 rows[0]["value"]

  client.rest.upsert TEST_TABLE
      --schema=TEST_SCHEMA
      {
        "id": rows[0]["id"],
        "value": 501,
      }
  rows = client.rest.select TEST_TABLE --schema=TEST_SCHEMA
  expect-equals 1 rows.size
  expect-equals 501 rows[0]["value"]

  client.rest.upsert TEST_TABLE
      --schema=TEST_SCHEMA
      {
        "id": rows[0]["id"] + 1,
        "value": 502,
      }
  rows = client.rest.select TEST_TABLE --schema=TEST_SCHEMA
  expect-equals 2 rows.size
  expect-equals 501 rows[0]["value"]
  expect-equals 502 rows[1]["value"]

  client.rest.delete TEST_TABLE
      --schema=TEST_SCHEMA
      --filters=[
        filter.equals "id" rows[0]["id"],
      ]
  rows = client.rest.select TEST_TABLE --schema=TEST_SCHEMA
  expect-equals 1 rows.size
  expect-equals 502 rows[0]["value"]

  rpc-value := client.rest.rpc "fun" --schema=TEST_SCHEMA {:}
  expect-equals 42 rpc-value
