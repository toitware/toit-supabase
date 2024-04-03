// Copyright (C) 2023 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the EXAMPLES_LICENSE file.

import encoding.json
import host.os
import host.file
import host.directory
import supabase
import system show platform PLATFORM_WINDOWS

// TODO(florian): A lot of this functionality should come from the CLI package.

/**
The base directory relative to which user-specific configuration files should be
  stored.
*/
config_home -> string?:
  xdg_result := os.env.get "XDG_CONFIG_HOME"
  if xdg_result: return xdg_result

  // All fallbacks are relative to the user's home directory.
  home := os.env.get "HOME"
  if not home and platform == PLATFORM_WINDOWS:
    home = os.env.get "USERPROFILE"

  if not home: throw "Could not determine home directory."

  return "$home/.config"


class ConfigLocalStorage implements supabase.LocalStorage:
  path_/string
  config_/Map
  auth_key_/string

  constructor --app_name/string --auth_key/string="":
    path_ = "$config_home/$app_name/auth"
    if file.is_file path_:
      content := file.read_content path_
      config_ = json.decode content
    else:
      config_ = {:}
    auth_key_ = auth_key

  has_auth -> bool:
    return config_.contains auth_key_

  get_auth -> any?:
    return config_.get auth_key_

  set_auth value/any:
    config_[auth_key_] = value
    write_

  remove_auth -> none:
    config_.remove auth_key_
    write_

  write_:
    config_dir := dirname_ path_
    directory.mkdir --recursive config_dir
    stream := file.Stream.for_write path_
    stream.out.write (json.encode config_)
    // TODO(florian): we would like to call 'close' here.
    // writer.close
    stream.close

  dirname_ path/string -> string:
    last_separator := path.index_of --last "/"
    if platform == PLATFORM_WINDOWS:
      last_separator = max last_separator (path.index_of --last "\\")
    if last_separator == -1: return "."
    return path[..last_separator]
