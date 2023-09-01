// Copyright (C) 2023 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the TESTS_LICENSE file.

import host.pipe
import host.os
import supabase

class Config implements supabase.ServerConfig:
  host/string
  anon/string

  constructor --.host --.anon:
  root_certificate_name -> string?: return null
  root_certificate_der -> ByteArray?: return null

get_supabase_config --sub_directory/string -> supabase.ServerConfig:
  anon_key/string? := null
  api_url/string? := null

  out := get_status_ sub_directory
  lines := out.split "\n"
  lines.map --in_place: it.trim
  lines.do:
    if it.starts_with "anon key:":
      anon_key = it[(it.index_of ":") + 1..].trim
    else if it.starts_with "API URL:":
      api_url = it[(it.index_of ":") + 1..].trim

  if not anon_key or not api_url:
    throw "Could not get supabase info"

  host := api_url.trim --left "http://"
  print_on_stderr_ "HOST: $host ANON_KEY: $anon_key"
  name := sub_directory.trim --left "../"
  return Config --host=host --anon=anon_key

get_supabase_service_key --sub_directory/string -> string:
  out := get_status_ sub_directory
  lines := out.split "\n"
  lines.map --in_place: it.trim
  lines.do:
    if it.starts_with "service_role key:":
      return it[(it.index_of ":") + 1..].trim
  unreachable

get_status_ sub_directory/string -> string:
  supabase_exe := os.env.get "SUPABASE_EXE" or "supabase"
  return pipe.backticks supabase_exe "--workdir" "$sub_directory" "status"
