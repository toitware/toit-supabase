-- Copyright (C) 2023 Toitware ApS.
-- Use of this source code is governed by a Zero-Clause BSD license that can
-- be found in the TESTS_LICENSE file.

CREATE TABLE filters (
  id SERIAL PRIMARY KEY,
  data TEXT,
  value INTEGER,
  valuef FLOAT,
  b BOOLEAN,
  int_array INTEGER[],
  dates TIMESTAMPTZ
);
