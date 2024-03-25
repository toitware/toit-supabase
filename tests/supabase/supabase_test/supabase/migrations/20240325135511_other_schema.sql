-- Copyright (C) 2024 Toitware ApS.
-- Use of this source code is governed by a Zero-Clause BSD license that can
-- be found in the TESTS_LICENSE file.

CREATE SCHEMA IF NOT EXISTS other_schema;

GRANT USAGE ON SCHEMA other_schema TO anon, authenticated, service_role;
GRANT ALL ON ALL TABLES IN SCHEMA other_schema TO anon, authenticated, service_role;
GRANT ALL ON ALL ROUTINES IN SCHEMA other_schema TO anon, authenticated, service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA other_schema TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA other_schema GRANT ALL ON TABLES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA other_schema GRANT ALL ON ROUTINES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA other_schema GRANT ALL ON SEQUENCES TO anon, authenticated, service_role;

CREATE TABLE other_schema.some_table (
  id SERIAL PRIMARY KEY,
  value INTEGER
);

CREATE FUNCTION other_schema.fun()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
BEGIN
  RETURN 42;
END;
$$;
