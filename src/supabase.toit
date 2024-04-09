// Copyright (C) 2023 Toitware ApS.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import http
import net
import net.x509
import http.status_codes
import encoding.json
import encoding.url
import io
import tls

import .auth
import .utils_ as utils
import .filter show Filter

interface ServerConfig:
  host -> string
  anon -> string
  root_certificate_name -> string?
  root_certificate_der -> ByteArray?

/**
An interface for interactions with the user.
*/
interface Ui:
  info str/string

/**
A client for the Supabase API.

Supabase provides several different APIs under one umbrella.

A frontend ('Kong'), takes the requests and forwards them to the correct
  backend.
Each supported backend is available through a different getter.
For example, the Postgres backend is available through the $rest getter, and
  the storage backend is available through $storage.
*/
class Client:
  http_client_/http.Client? := null
  local_storage_/LocalStorage
  session_/Session_? := null

  /**
  The used network interface.
  This field is only set, if the $close function should close the network.
  */
  network_to_close_/net.Interface? := null

  /**
  The host of the Supabase project.
  */
  host_/string

  /**
  The anonymous key of the Supabase project.

  This key is used as api key.
  If the user is not authenticated the client uses this key as the bearer.
  */
  anon_/string

  rest_/PostgRest? := null
  storage_/Storage? := null
  auth_/Auth? := null

  constructor network/net.Interface?=null
      --host/string
      --anon/string
      --local_storage/LocalStorage=NoLocalStorage:
    host_ = host
    anon_ = anon

    if not network:
      network = network_to_close_ = net.open

    http_client_ = http.Client network
    local_storage_ = local_storage
    add_finalizer this:: close

  constructor.tls network/net.Interface?=null
      --host/string
      --anon/string
      --root_certificates/List=[]
      --local_storage/LocalStorage=NoLocalStorage:
    host_ = host
    anon_ = anon

    if not network:
      network = network_to_close_ = net.open

    http_client_ = http.Client.tls network --root_certificates=root_certificates
    local_storage_ = local_storage
    add_finalizer this:: close

  constructor network/net.Interface?=null
      --server_config/ServerConfig
      --local_storage/LocalStorage=NoLocalStorage
      [--certificate_provider]:
    root_certificate := server_config.root_certificate_der
    if not root_certificate and server_config.root_certificate_name:
      root_certificate = certificate_provider.call server_config.root_certificate_name

    if root_certificate:
      root_certificate_der := ?
      if root_certificate is tls.RootCertificate:
        root_certificate_der = (root_certificate as tls.RootCertificate).raw
      else:
        root_certificate_der = root_certificate
      certificate := x509.Certificate.parse root_certificate_der
      return Client.tls network
          --local_storage=local_storage
          --host=server_config.host
          --anon=server_config.anon
          --root_certificates=[certificate]
    else:
      return Client network
          --host=server_config.host
          --anon=server_config.anon
          --local_storage=local_storage

  /**
  Ensures that the user is authenticated.

  If a session is stored in the local storage and is still valid, uses that
    session. In that case no network request is made. If the session has been
    invalidated in the meantime an error will happen at later point in time.

  If no session is stored, or the refresh failed, calls the given $block with the
    reason for why the client isn't authenticated. This could include an error
    when refreshing an authorization token. In most cases it's simply "Not logged in".

  # Examples
  A simple example where the user is signed in using email and password:
  ```
  client.ensure_authenticated: | reason/string |
    print "Authentication failure: $reason"
    client.auth.sign_in --email="email" --password="password"
  ```

  Or, using oauth:
  ```
  client.ensure_authenticated: | reason/string |
    print "Authentication failure: $reason"
    client.auth.sign_in --provider="github" --ui=ui
  ```
  */
  ensure_authenticated [block]:
    exception := null
    if local_storage_.has_auth:
      exception = catch:
        session_ = Session_.from_json local_storage_.get_auth
        if session_.has_expired --min_remaining=(Duration --m=20):
          auth.refresh_token
        return
      // There was an exception.
      // Clear the stored session, and run the block for a fresh authentication.
      local_storage_.remove_auth
    reason := ?
    if exception:
      reason = "Error while refreshing the authentication: $exception"
    else:
      reason = "Not logged in"
    block.call reason

  close -> none:
    if not http_client_: return
    remove_finalizer this
    http_client_.close
    http_client_ = null
    if network_to_close_:
      network_to_close_.close
      network_to_close_ = null

  is_closed -> bool:
    return http_client_ == null

  rest -> PostgRest:
    if not rest_: rest_ = PostgRest this
    return rest_

  storage -> Storage:
    if not storage_: storage_ = Storage this
    return storage_

  auth -> Auth:
    if not auth_: auth_ = Auth this
    return auth_

  set_session_ session/Session_?:
    session_ = session
    if session:
      local_storage_.set_auth session.to_json
    else:
      local_storage_.remove_auth

  is_success_status_code_ code/int -> bool:
    return 200 <= code <= 299

  /**
  Does a request to the Supabase API, and returns the response without
    parsing it.

  It is the responsibility of the caller to drain the response.

  Query parameters can be provided in two ways:
  - with the $query parameter is a string that is appended to the path. It must
    be properly URL encoded (also known as percent-encoding), or
  - with the $query_parameters parameter, which is a map from keys to values.
    The value for each key must be a string or a list of strings. In the latter
    case, each value is added as a separate query parameter.
  It is an error to provide both $query and $query_parameters.
  */
  request_ --raw_response/bool -> http.Response
      --path/string
      --method/string
      --bearer/string? = null
      --query/string? = null
      --query_parameters/Map? = null
      --headers/http.Headers? = null
      --payload/any = null
      --schema/string? = null:

    if query and query_parameters:
      throw "Cannot provide both query and query_parameters"

    headers = headers ? headers.copy : http.Headers

    if not bearer:
      if not session_: bearer = anon_
      else: bearer = session_.access_token
    headers.set "Authorization" "Bearer $bearer"

    headers.add "apikey" anon_

    if schema:
      if method == http.GET or method == http.HEAD:
        headers.add "Accept-Profile" schema
      else:
        headers.add "Content-Profile" schema

    question_mark_pos := path.index_of "?"
    if question_mark_pos >= 0:
      // Replace the existing query parameters with ours.
      path = path[..question_mark_pos]
    if query_parameters:
      encoded_params := []
      query_parameters.do: | key value |
        encoded_key := url.encode key
        if value is List:
          value.do:
            encoded_params.add "$encoded_key=$(url.encode it)"
        else:
          encoded_params.add "$encoded_key=$(url.encode value)"
      path = "$path?$(encoded_params.join "&")"
    else if query:
      path = "$path?$query"

    host := host_
    port := null
    colon_pos := host.index_of ":"
    if colon_pos >= 0:
      host = host_[..colon_pos]
      port = int.parse host_[colon_pos + 1..]

    response/http.Response := ?
    if method == http.GET:
      if payload: throw "GET requests cannot have a payload"
      response = http_client_.get --host=host --port=port --path=path --headers=headers
    else if method == http.PATCH or method == http.DELETE or method == http.PUT:
      // TODO(florian): the http client should support PATCH.
      // TODO(florian): we should only do this if the payload is a Map.
      encoded := json.encode payload
      headers.set "Content-Type" "application/json"
      request := http_client_.new_request method
          --host=host
          --port=port
          --path=path
          --headers=headers
      request.body = io.Reader encoded
      response = request.send
    else:
      if method != http.POST: throw "UNIMPLEMENTED"
      if payload is Map:
        response = http_client_.post_json payload
            --host=host
            --port=port
            --path=path
            --headers=headers
      else:
        response = http_client_.post payload
            --host=host
            --port=port
            --path=path
            --headers=headers

    return response

  /**
  Variant of $(request_ --raw_response --path --method).

  Does a request to the Supabase API, and extracts the response.
  If $parse_response_json is true, then parses the response as a JSON
    object.
  Otherwise returns it as a byte array.
  */
  request_ -> any
      --path/string
      --method/string
      --bearer/string? = null
      --query/string? = null
      --query_parameters/Map? = null
      --headers/http.Headers? = null
      --parse_response_json/bool = true
      --payload/any = null
      --schema/string? = null:
    response := request_
        --raw_response
        --path=path
        --method=method
        --bearer=bearer
        --query=query
        --query_parameters=query_parameters
        --headers=headers
        --payload=payload
        --schema=schema

    body := response.body
    if not is_success_status_code_ response.status_code:
      body_bytes := utils.read_all body
      message := ""
      exception := catch:
        decoded := json.decode body_bytes
        message = decoded.get "msg" or
            decoded.get "message" or
            decoded.get "error_description" or
            decoded.get "error" or
            body_bytes.to_string_non_throwing
      if exception:
        message = body_bytes.to_string_non_throwing
      throw "FAILED: $response.status_code - $message"

    if not parse_response_json:
      return (utils.read_all body).to_string_non_throwing

    // Still check whether there is a response.
    // When performing an RPC we can't know in advance whether the function
    // returns something or not.
    buffered_body := body
    if not buffered_body.try-ensure-buffered 1:
      return null

    try:
      return json.decode_stream buffered_body
    finally:
      catch: response.drain

/**
An interface to store authentication information locally.

On desktops this should be the config file.
On mobile this could be something like HiveDB/Isar.
*/
interface LocalStorage:
  /**
  Whether the storage contains any authorization information.
  */
  has_auth -> bool

  /**
  Returns the stored authorization information.
  If none exists, returns null.
  */
  get_auth -> any?

  /**
  Sets the authorization information to $value.

  The $value must be JSON-encodable.
  */
  set_auth value/any -> none

  /**
  Removes any authorization information.
  */
  remove_auth -> none

/**
A simple implementation of $LocalStorage that simply discards all data.
*/
class NoLocalStorage implements LocalStorage:
  has_auth -> bool: return false
  get_auth -> any?: return null
  set_auth value/any: return
  remove_auth -> none: return

/**
A client for the PostgREST API.

PostgREST uses 'GET', 'POST', 'PATCH', 'PUT', and 'DELETE' requests to
  perform CRUD operations on tables.

- 'GET' requests are used to retrieve rows from a table.
- 'POST' requests are used to insert rows into a table.
- 'PATCH' requests are used to update rows in a table.
- 'PUT' requests are used to replace a single row in a table.
- 'DELETE' requests are used to delete rows from a table.
*/
class PostgRest:
  /**
  For 'POST' requests (inserts), the response is empty, and only
    contains a 'Location' header with the primary key of the newly
    inserted row.
  This return preference must not be used for other requests.

  Note that this return preference leads to a permission error if the
    table is only write-only.
  */
  static RETURN_HEADER_ONLY_ ::= "header-only"
  /**
  The response is the full representation.

  This return preference is allowed for 'POST', 'PATCH', 'DELETE' and
    'PUT' requests.
  */
  static RETURN_REPRESENTATION_ ::= "representation"
  /**
  The response does not include the 'Location' header, as would be
    the case with 'RETURN_HEADER_ONLY'. This return preference must
    be used when writing into a table that is write-only.

  This return preference is allowed for 'POST', 'PATCH', 'DELETE' and
    'PUT' requests.
  */
  static RETURN_MINIMAL_ ::= "minimal"

  client_/Client

  constructor .client_:

  encode_filters_ filters/List -> string:
    escaped := filters.map: | filter/Filter |
      filter.to_string --nested=false --negated=false
    return escaped.join "&"

  /**
  Returns a list of rows that match the $filters.

  The $filters must be instances of the $Filter class.
  */
  select table/string --filters/List=[] --schema/string?=null -> List:
    query_filters := encode_filters_ filters
    return client_.request_
        --method=http.GET
        --path="/rest/v1/$table"
        --query=query_filters
        --schema=schema

  /**
  Inserts a new row to the table.

  If the row would violate a unique constraint, then the operation fails.

  If $return_inserted is true, then returns the inserted row.
  */
  insert -> Map?
      table/string
      payload/Map
      --return_inserted/bool=true
      --schema/string?=null:
    headers := http.Headers
    headers.add "Prefer" "return=$(return_inserted ? RETURN_REPRESENTATION_ : RETURN_MINIMAL_)"
    response := client_.request_
        --method=http.POST
        --headers=headers
        --path="/rest/v1/$table"
        --payload=payload
        --parse_response_json=return_inserted
        --schema=schema
    if return_inserted:
      return response.size == 0 ? null : response[0]
    return null

  /**
  Performs an 'update' operation on a table.

  The $filters must be instances of the $Filter class.
  */
  update table/string payload/Map --filters/List --schema/string?=null -> none:
    query_filters := encode_filters_ filters
    // We are not using the response. Use the minimal response.
    headers := http.Headers
    headers.add "Prefer" RETURN_MINIMAL_
    client_.request_
        --method=http.PATCH
        --headers=headers
        --path="/rest/v1/$table"
        --payload=payload
        --parse_response_json=false
        --query=query_filters
        --schema=schema

  /**
  Performs an 'upsert' operation on a table.

  The word "upsert" is a combination of "update" and "insert".
  If adding a row would violate a unique constraint, then the row is
    updated instead.
  */
  upsert -> none
      table/string
      payload/Map
      --ignore_duplicates/bool=false
      --schema/string?=null:
    // TODO(florian): add support for '--on_conflict'.
    // In that case the conflict detection is on the column given by
    // on_column (which must be 'UNIQUE').
    // Verify this, and add the parameter.
    headers := http.Headers
    preference := ignore_duplicates
        ? "resolution=ignore-duplicates"
        : "resolution=merge-duplicates"
    headers.add "Prefer" preference
    // We are not using the response. Use the minimal response.
    headers.add "Prefer" RETURN_MINIMAL_
    client_.request_
        --method=http.POST
        --headers=headers
        --path="/rest/v1/$table"
        --payload=payload
        --parse_response_json=false
        --schema=schema

  /**
  Deletes all rows that match the filters.

  If no filters are given, then all rows are deleted. Note that some
    server configurations require at least one filter for a delete
    operation.

  The $filters must be instances of the $Filter class.
  */
  delete table/string --filters/List --schema/string?=null -> none:
    query_filters := encode_filters_ filters
    // We are not using the response. Use the minimal response.
    headers := http.Headers
    headers.add "Prefer" RETURN_MINIMAL_
    client_.request_
        --method=http.DELETE
        --headers=headers
        --path="/rest/v1/$table"
        --parse_response_json=false
        --query=query_filters
        --schema=schema

  /**
  Performs a remote procedure call (RPC).
  */
  rpc name/string payload/Map --schema/string?=null -> any:
    return client_.request_
        --method=http.POST
        --path="/rest/v1/rpc/$name"
        --payload=payload
        --schema=schema

class Storage:
  client_/Client

  constructor .client_:

  // TODO(florian): add support for changing and deleting.
  // TODO(florian): add support for 'get_public_url'.
  //    should be as simple as "$url/storage/v1/object/public/$path"

  /**
  Uploads data to the storage.

  If $upsert is true, then the data is overwritten if it already exists.
  */
  upload --path/string --content/ByteArray --upsert/bool=true -> none:
    headers := http.Headers
    if upsert: headers.add "x-upsert" "true"
    headers.add "Content-Type" "application/octet-stream"
    client_.request_
        --method=http.POST
        --headers=headers
        --path="/storage/v1/object/$path"
        --payload=content
        --parse_response_json=false

  /**
  Downloads the data stored in $path from the storage.

  If $public is true, downloads the data through the public URL.
  */
  download --path/string --public/bool=false -> ByteArray:
    download --path=path --public=public: | reader/io.Reader |
      return utils.read_all reader
    unreachable

  /**
  Downloads the data stored in $path from the storage.

  Calls the given $block with an $io.Reader for the resource.

  If $public is true, downloads the data through the public URL.
  */
  download --public/bool=false --path/string --offset/int=0 --size/int?=null [block] -> none:
    partial := false
    headers/http.Headers? := null
    if offset != 0 or size:
      partial = true
      end := size ? "$(offset + size - 1)" : ""
      headers = http.Headers
      headers.add "Range" "bytes=$offset-$end"
    full_path := public
        ? "storage/v1/object/public/$path"
        : "storage/v1/object/$path"
    response := client_.request_ --raw_response
        --method=http.GET
        --path=full_path
        --headers=headers
    // Check the status code. The correct result depends on whether
    // or not we're doing a partial fetch.
    status := response.status_code
    body := response.body
    okay := status == status_codes.STATUS_OK or (partial and status == status_codes.STATUS_PARTIAL_CONTENT)
    try:
      if not okay: throw "Not found ($status)"
      block.call body
    finally:
      catch: response.drain

  /**
  Returns a list of all buckets.
  */
  list_buckets -> List:
    return client_.request_
        --method=http.GET
        --path="/storage/v1/bucket"
        --parse_response_json=true

  /**
  Returns a list of all objects at the given path.
  The path must not be empty.
  */
  list path/string -> List:
    if path == "": throw "INVALID_ARGUMENT"
    first_slash := path.index_of "/"
    bucket/string := ?
    prefix/string := ?
    if first_slash == -1:
      bucket = path
      prefix = ""
    else:
      bucket = path[0..first_slash]
      prefix = path[first_slash + 1..path.size]

    payload := {
      "prefix": prefix,
    }
    return client_.request_
        --method=http.POST
        --path="/storage/v1/object/list/$bucket"
        --parse_response_json=true
        --payload=payload

  /**
  Computes the public URL for the given $path.
  */
  public_url_for --path/string -> string:
    return "$client_.host_/storage/v1/object/public/$path"
