-- Copyright (C) 2023 Toitware ApS. All rights reserved.

CREATE TABLE filters (
  id SERIAL PRIMARY KEY,
  data TEXT,
  value INTEGER,
  valuef FLOAT,
  b BOOLEAN,
  int_array INTEGER[],
  dates TIMESTAMPTZ
);
