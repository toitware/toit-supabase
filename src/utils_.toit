// Copyright (C) 2023 Toitware ApS.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import io
import io show Reader

// TODO(kasper): This is unlikely to be the best place to share this
// code. Should we consider having this as part of the core libraries?
read_all reader/Reader -> ByteArray:
  size/int? := reader.content-size

  first := reader.read
  if not first:
    if size and size > 0: throw Reader.UNEXPECTED_END_OF_READER
    return #[]

  second := reader.read
  if not second:
    if size:
      missing := size - first.size
      if missing > 0: throw Reader.UNEXPECTED_END_OF_READER
      else if missing < 0: throw "OUT_OF_BOUNDS"
    return first

  if size:
    result := ByteArray size
    result.replace 0 first
    offset := first.size
    first = null  // Allow garbage collection.
    result.replace offset second
    offset += second.size
    second = null  // Allow garbage collection.
    while chunk := reader.read:
      result.replace offset chunk
      offset += chunk.size
    if offset != size: throw Reader.UNEXPECTED_END_OF_READER
    return result
  else:
    buffer := io.Buffer.with-capacity first.size + second.size
    buffer.write first
    first = null  // Allow garbage collection.
    buffer.write second
    second = null  // Allow garbage collection.
    while chunk := reader.read: buffer.write chunk
    return buffer.bytes
