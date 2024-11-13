// Copyright (C) 2023 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the EXAMPLES_LICENSE file.

import encoding.json
import host.os
import host.file
import host.directory
import supabase
import system show platform PLATFORM-WINDOWS

// TODO(florian): A lot of this functionality should come from the CLI package.

/**
The base directory relative to which user-specific configuration files should be
  stored.
*/
config-home -> string?:
  xdg-result := os.env.get "XDG_CONFIG_HOME"
  if xdg-result: return xdg-result

  // All fallbacks are relative to the user's home directory.
  home := os.env.get "HOME"
  if not home and platform == PLATFORM-WINDOWS:
    home = os.env.get "USERPROFILE"

  if not home: throw "Could not determine home directory."

  return "$home/.config"


class ConfigLocalStorage implements supabase.LocalStorage:
  path_/string
  config_/Map
  auth-key_/string

  constructor --app-name/string --auth-key/string="":
    path_ = "$config-home/$app-name/auth"
    if file.is-file path_:
      contents := file.read-contents path_
      config_ = json.decode contents
    else:
      config_ = {:}
    auth-key_ = auth-key

  has-auth -> bool:
    return config_.contains auth-key_

  get-auth -> any?:
    return config_.get auth-key_

  set-auth value/any:
    config_[auth-key_] = value
    write_

  remove-auth -> none:
    config_.remove auth-key_
    write_

  write_:
    config-dir := dirname_ path_
    directory.mkdir --recursive config-dir
    stream := file.Stream.for-write path_
    stream.out.write (json.encode config_)
    // TODO(florian): we would like to call 'close' here.
    // writer.close
    stream.close

  dirname_ path/string -> string:
    last-separator := path.index-of --last "/"
    if platform == PLATFORM-WINDOWS:
      last-separator = max last-separator (path.index-of --last "\\")
    if last-separator == -1: return "."
    return path[..last-separator]
