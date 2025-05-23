## Transport module for nim-libs
## Provides unified transport layer for protocol communication (LSP, DAP, etc.)

import std/[asyncdispatch, asyncnet, json, strutils, strformat, streams]
import ./errors
import ./logging

# Export commonly used types
export asyncdispatch, json

const
  DefaultBufferSize* = 8192
  DefaultHeaderDelimiter* = "\r\n\r\n"

type
  TransportError* = object of AppError
    ## Error type for transport operations
  
  TransportKind* = enum
    ## Type of transport
    tkStdio
    tkSocket
    tkServer
  
  ConnectionState* = enum
    ## Connection states
    csDisconnected
    csConnecting
    csConnected
    csDisconnecting
  
  MessageHeader* = object
    ## Message header information
    contentLength*: int
    contentType*: string
  
  Transport* = ref object of RootObj
    ## Base transport type
    state*: ConnectionState
    logger*: Logger
  
  StdioTransport* = ref object of Transport
    ## Standard I/O transport for stdio communication
  
  SocketTransport* = ref object of Transport
    ## Socket transport for client connections
    host*: string
    port*: int
    client*: AsyncSocket
  
  ServerTransport* = ref object of Transport
    ## Server transport for accepting connections
    host*: string
    port*: int
    server*: AsyncSocket
    client*: AsyncSocket
  
  Message* = JsonNode
    ## Alias for message type

# Error constructors
proc newTransportError*(msg: string, code = ecInvalidInput): ref TransportError =
  result = newException(TransportError, msg)
  result.context = newErrorContext(code, msg)

# Base transport methods
method start*(t: Transport): Future[void] {.base, async.} =
  ## Start the transport
  raise newTransportError("Not implemented")

method stop*(t: Transport): Future[void] {.base, async.} =
  ## Stop the transport
  t.state = csDisconnecting
  t.state = csDisconnected
  if not t.logger.isNil:
    t.logger.debug("Transport stopped")

method isConnected*(t: Transport): bool {.base.} =
  ## Check if transport is connected
  return t.state == csConnected

method sendMessage*(t: Transport, message: Message): Future[void] {.base, async.} =
  ## Send a message through the transport
  raise newTransportError("Not implemented")

method receiveMessage*(t: Transport): Future[Message] {.base, async.} =
  ## Receive a message from the transport
  raise newTransportError("Not implemented")

# Header parsing
proc parseHeader*(headerLine: string): tuple[name: string, value: string] =
  ## Parse a header line into name and value
  let parts = headerLine.split(":", 1)
  if parts.len != 2:
    raise newTransportError("Invalid header format: " & headerLine)
  result.name = parts[0].strip().toLower()
  result.value = parts[1].strip()

proc parseHeaders*(headerBlock: string): MessageHeader =
  ## Parse a block of headers
  result.contentLength = -1
  
  for line in headerBlock.splitLines():
    if line.strip().len == 0:
      continue
    
    let (name, value) = parseHeader(line)
    case name
    of "content-length":
      try:
        result.contentLength = parseInt(value)
      except ValueError:
        raise newTransportError("Invalid Content-Length: " & value)
    of "content-type":
      result.contentType = value
    else:
      # Ignore unknown headers
      discard

proc createHeader*(contentLength: int, contentType = ""): string =
  ## Create a message header
  result = fmt"Content-Length: {contentLength}{DefaultHeaderDelimiter}"
  if contentType.len > 0:
    result = fmt"Content-Type: {contentType}\r\n" & result

# Stdio transport implementation
proc newStdioTransport*(logger: Logger = nil): StdioTransport =
  ## Create a new stdio transport
  result = StdioTransport(
    state: csDisconnected,
    logger: if logger.isNil: newLogger("StdioTransport") else: logger
  )

method start*(t: StdioTransport): Future[void] {.async.} =
  ## Start stdio transport
  t.state = csConnecting
  t.state = csConnected
  if not t.logger.isNil:
    t.logger.debug("Stdio transport started")

method sendMessage*(t: StdioTransport, message: Message): Future[void] {.async.} =
  ## Send message through stdio
  if t.state != csConnected:
    raise newTransportError("Transport not connected")
  
  let content = $message
  let header = createHeader(content.len)
  stdout.write(header & content)
  stdout.flushFile()
  
  if not t.logger.isNil:
    t.logger.debug("Sent message", %*{"length": content.len})

method receiveMessage*(t: StdioTransport): Future[Message] {.async.} =
  ## Receive message from stdio
  if t.state != csConnected:
    raise newTransportError("Transport not connected")
  
  var headers = ""
  
  # Read headers
  while true:
    let line = stdin.readLine()
    if line == "":
      break
    headers &= line & "\n"
  
  # Parse headers
  let header = parseHeaders(headers)
  if header.contentLength <= 0:
    raise newTransportError("Missing or invalid Content-Length header")
  
  # Read content
  var buffer = newString(header.contentLength)
  let bytesRead = stdin.readBuffer(buffer.cstring, header.contentLength)
  if bytesRead != header.contentLength:
    raise newTransportError(fmt"Expected {header.contentLength} bytes, got {bytesRead}")
  
  try:
    result = parseJson(buffer)
    if not t.logger.isNil:
      t.logger.debug("Received message", %*{"length": header.contentLength})
  except JsonParsingError as e:
    raise newTransportError("Invalid JSON: " & e.msg)

# Socket transport implementation
proc newSocketTransport*(host: string, port: int, logger: Logger = nil): SocketTransport =
  ## Create a new socket transport
  result = SocketTransport(
    host: host,
    port: port,
    state: csDisconnected,
    logger: if logger.isNil: newLogger("SocketTransport") else: logger
  )

method start*(t: SocketTransport): Future[void] {.async.} =
  ## Start socket transport (connect to server)
  if t.state == csConnected:
    raise newTransportError("Already connected")
  
  t.state = csConnecting
  t.client = newAsyncSocket()
  
  try:
    await t.client.connect(t.host, Port(t.port))
    t.state = csConnected
    if not t.logger.isNil:
      t.logger.info("Connected to", %*{"host": t.host, "port": t.port})
  except:
    t.state = csDisconnected
    raise newTransportError(fmt"Failed to connect to {t.host}:{t.port}")

method stop*(t: SocketTransport): Future[void] {.async.} =
  ## Stop socket transport
  if not t.client.isNil:
    t.client.close()
  procCall stop(Transport(t))

method sendMessage*(t: SocketTransport, message: Message): Future[void] {.async.} =
  ## Send message through socket
  if t.state != csConnected or t.client.isNil:
    raise newTransportError("Not connected")
  
  let content = $message
  let header = createHeader(content.len)
  await t.client.send(header & content)
  
  if not t.logger.isNil:
    t.logger.debug("Sent message", %*{"length": content.len})

method receiveMessage*(t: SocketTransport): Future[Message] {.async.} =
  ## Receive message from socket
  if t.state != csConnected or t.client.isNil:
    raise newTransportError("Not connected")
  
  var headers = ""
  
  # Read headers
  while true:
    let line = await t.client.recvLine()
    if line == "":
      break
    headers &= line & "\n"
  
  # Parse headers
  let header = parseHeaders(headers)
  if header.contentLength <= 0:
    raise newTransportError("Missing or invalid Content-Length header")
  
  # Read content
  let content = await t.client.recv(header.contentLength)
  if content.len != header.contentLength:
    raise newTransportError(fmt"Expected {header.contentLength} bytes, got {content.len}")
  
  try:
    result = parseJson(content)
    if not t.logger.isNil:
      t.logger.debug("Received message", %*{"length": header.contentLength})
  except JsonParsingError as e:
    raise newTransportError("Invalid JSON: " & e.msg)

# Server transport implementation
proc newServerTransport*(host: string, port: int, logger: Logger = nil): ServerTransport =
  ## Create a new server transport
  result = ServerTransport(
    host: host,
    port: port,
    state: csDisconnected,
    logger: if logger.isNil: newLogger("ServerTransport") else: logger
  )

method start*(t: ServerTransport): Future[void] {.async.} =
  ## Start server transport (accept connections)
  if t.state == csConnected:
    raise newTransportError("Already connected")
  
  t.state = csConnecting
  t.server = newAsyncSocket()
  t.server.setSockOpt(OptReuseAddr, true)
  
  try:
    t.server.bindAddr(Port(t.port), t.host)
    t.server.listen()
    
    if not t.logger.isNil:
      t.logger.info("Listening on", %*{"host": t.host, "port": t.port})
    
    t.client = await t.server.accept()
    t.state = csConnected
    
    if not t.logger.isNil:
      t.logger.info("Client connected")
  except:
    t.state = csDisconnected
    raise newTransportError(fmt"Failed to start server on {t.host}:{t.port}")

method stop*(t: ServerTransport): Future[void] {.async.} =
  ## Stop server transport
  if not t.client.isNil:
    t.client.close()
  if not t.server.isNil:
    t.server.close()
  procCall stop(Transport(t))

method sendMessage*(t: ServerTransport, message: Message): Future[void] {.async.} =
  ## Send message to connected client
  if t.state != csConnected or t.client.isNil:
    raise newTransportError("No client connected")
  
  let content = $message
  let header = createHeader(content.len)
  await t.client.send(header & content)
  
  if not t.logger.isNil:
    t.logger.debug("Sent message", %*{"length": content.len})

method receiveMessage*(t: ServerTransport): Future[Message] {.async.} =
  ## Receive message from connected client
  if t.state != csConnected or t.client.isNil:
    raise newTransportError("No client connected")
  
  var headers = ""
  
  # Read headers
  while true:
    let line = await t.client.recvLine()
    if line == "":
      break
    headers &= line & "\n"
  
  # Parse headers
  let header = parseHeaders(headers)
  if header.contentLength <= 0:
    raise newTransportError("Missing or invalid Content-Length header")
  
  # Read content
  let content = await t.client.recv(header.contentLength)
  if content.len != header.contentLength:
    raise newTransportError(fmt"Expected {header.contentLength} bytes, got {content.len}")
  
  try:
    result = parseJson(content)
    if not t.logger.isNil:
      t.logger.debug("Received message", %*{"length": header.contentLength})
  except JsonParsingError as e:
    raise newTransportError("Invalid JSON: " & e.msg)

# Factory function for creating transports
proc createTransport*(kind: TransportKind, host = "localhost", port = 0, logger: Logger = nil): Transport =
  ## Create a transport of the specified kind
  case kind
  of tkStdio:
    result = newStdioTransport(logger)
  of tkSocket:
    result = newSocketTransport(host, port, logger)
  of tkServer:
    result = newServerTransport(host, port, logger)

# Utility functions for testing and debugging
proc readMessageFromStream*(stream: Stream): Message =
  ## Read a message from a synchronous stream (for testing)
  var headers = ""
  
  # Read headers
  while true:
    let line = stream.readLine()
    if line == "":
      break
    headers &= line & "\n"
  
  # Parse headers
  let header = parseHeaders(headers)
  if header.contentLength <= 0:
    raise newTransportError("Missing or invalid Content-Length header")
  
  # Read content
  let content = stream.readStr(header.contentLength)
  try:
    result = parseJson(content)
  except JsonParsingError as e:
    raise newTransportError("Invalid JSON: " & e.msg)

proc writeMessageToStream*(stream: Stream, message: Message) =
  ## Write a message to a synchronous stream (for testing)
  let content = $message
  let header = createHeader(content.len)
  stream.write(header & content)
  stream.flush()