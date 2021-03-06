# Elixir Thrift

[![Hex Version](https://img.shields.io/hexpm/v/thrift.svg)](https://hex.pm/packages/thrift)
[![Hex Docs](https://img.shields.io/badge/docs-hexpm-blue.svg)](https://hexdocs.pm/thrift/)
[![Build Status](https://travis-ci.org/pinterest/elixir-thrift.svg?branch=master)](https://travis-ci.org/pinterest/elixir-thrift)
[![Coverage Status](https://coveralls.io/repos/pinterest/elixir-thrift/badge.svg?branch=master)](https://coveralls.io/github/pinterest/elixir-thrift?branch=master)

This package contains an implementation of [Thrift](https://thrift.apache.org/)
for Elixir. It includes a Thrift IDL parser, an Elixir code generator, and
binary framed client and server implementations.

The generated serialization code is highly optimized and has been measured at
**10 and 25 times faster**<sub>[why?](#why-is-it-faster-than-the-apache-implementation)</sub>
than the code generated by the Apache Thrift Erlang implementation.

## Project Status

[Version 2.0](https://github.com/pinterest/elixir-thrift/milestone/1) is under
actively development and should be released soon. It is a complete rewrite
that drops the Apache Thrift dependency and implements everything in pure
Elixir.

## Getting Started

Until version 2.0 is released, you'll need to track the master branch
directly:

```elixir
{:thrift, github: "pinterest/elixir-thrift"}
```

This package includes a Mix compiler task that automates Thrift code
generation. Prepend `:thrift` to your project's `:compilers` list and add a
new top-level `:thrift` configuration key. The only necessary compiler option
is `:files`, which defines the list of Thrift files that should be compiled.

```elixir
# mix.exs
defmodule MyProject.Mixfile do
  # ...
  def project do
    [
      # ...
      compilers: [:thrift | Mix.compilers],
      thrift: [
        files: Path.wildcard("thrift/**/*.thrift")
      ]
    ]
  end
end
```

## RPC Service Support

We provide full client and server support for Thrift RPC services. The examples
below are based on this simplified service definition:

```thrift
service Service {
  i64 add(1: i64 left, 2: i64 right)
}
```

You can also check out the [full example project](example/) for a complete
client and server implementation of the sample calculator application.

### Clients

You interact with Thrift services using generated, service-specific interface
modules. These modules handle type conversions and make calling the service's
remote functions easier.

```elixir
iex> alias Calculator.Generated.Service.Binary.Framed.Client
iex> {:ok, client} = Client.start_link("localhost", 9090, [])
iex> {:ok, result} = Client.add(client, 10, 20)
{:ok, 30}
```

We generate two versions of each function defined by the Thrift service's
interface: one that returns a standard result tuple, and a `!` variant that
returns a single result value but raises an exception if an error occurs.

```elixir
@spec add(pid(), integer(), integer(), Client.options()) :: {:ok, integer()} | {:error, any()}
def add(client, left, right, rpc_opts \\ [])

@spec add!(pid(), integer(), integer(), Client.options()) :: integer()
def add!(client, left, right, rpc_opts \\ [])
```

### Servers

In order to start a Thrift server, you will need to provide a callback module
that implements the functions described by its service interface. Fortunately,
a [behaviour] module will be automatically generated for you, complete with
success typing.

```elixir
defmodule Calculator.ServiceHandler do
  @behaviour Calculator.Generated.Service.Handler

  @impl true
  def add(left, right) do
    left + right
  end
end
```

Then provide your handler module when starting the server process:

```elixir
iex> alias Calculator.Generated.Service.Binary.Framed.Server
iex> {:ok, server} = Server.start_link(Calculator.ServiceHandler, 9090, [])
```

All RPC calls to the server will be delegated to the handler module. The server
provides a [supervisor] which can be added to your application's supervision
tree. It's important to add it to your supervision tree with type `:supervisor`
and not `:worker`.

```elixir
defmodule Calculator.Application
  alias Calculator.Generated.Service.Binary.Framed.Server

  def start(_type, _args) do
    children = [
      server_child_spec(9090)
    ]

    opts = [strategy: :one_for_one, name: Calculator.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp server_child_spec(port) do
    %{
      id: Server,
      start: {Server, :start_link, [Calculator.ServiceHandler, port]},
      type: :supervisor
    }
  end
end
```

[behaviour]: https://elixir-lang.org/getting-started/typespecs-and-behaviours.html#behaviours
[supervisor]: https://elixir-lang.org/getting-started/mix-otp/supervisor-and-application.html

## Serialization

A `BinaryProtocol` module is generated for each Thrift struct, union, and
exception type. You can use this interface to easily serialize and deserialize
your own types.

```elixir
iex> alias Calculator.Generated.Vector
iex> data = %Vector{x: 1, y: 2, z: 3}
|> Vector.BinaryProtocol.serialize
|> IO.iodata_to_binary
iex> Vector.BinaryProtocol.deserialize(data)
{%Calculator.Generated.Vector{x: 1.0, y: 2.0, z: 3.0}, ""}
```

## Thrift IDL Parsing

The `Thrift.Parser` module parses [Thrift IDL][idl] documents and produces an
abstract syntax tree. You can use these features to support additional
languages, protocols, and servers.

```elixir
Thrift.Parser.parse("enum Colors { RED, GREEN, BLUE }")
%Thrift.AST.Schema{constants: %{},
 enums: %{Colors: %Thrift.AST.TEnum{name: :Colors,
    values: [RED: 1, GREEN: 2, BLUE: 3]}}, exceptions: %{}, includes: [],
 namespaces: %{}, services: %{}, structs: %{}, thrift_namespace: nil,
 typedefs: %{}, unions: %{}}
```

[idl]: https://thrift.apache.org/docs/idl

## Debugging

In order to debug your Thrift RPC calls, we recommend you use [`thrift-tools`](https://github.com/pinterest/thrift-tools). It is a set of tools to introspect Apache Thrift traffic.

Try something like:

```
$ pip install thrift-tools
$ sudo thrift-tool --iface eth0 --port 9090 dump --show-all --pretty
```

## FAQ

### Why is it faster than the Apache implementation?

The Apache Thrift implementation uses C++ to write Erlang modules that describe
Thrift data structures and then uses these descriptions to turn your Thrift
data into bytes. It consults these descriptions every time Thrift data is
serialized/deserialized. This on-the-fly conversion costs CPU time.

Additionally, this separation of concerns in Apache Thrift prevent the Erlang
VM from doing the best job that it can do during serialization.

Our implementation uses Elixir to write Elixir code that's specific to _your_
Thrift structures. This serialization logic is then compiled, and that compiled
code is what converts your data to and from serialized bytes. We've spent a lot
of time making sure that the generated code takes advantage of several of the
optimizations that the Erlang VM provides.

### What tradeoffs have you made to get this performance?

Thrift has the following concepts:

1. **Protocols** Define a conversion of data into bytes.
2. **Transports** Define how bytes move; across a network or in and out of a file.
3. **Processors** Encapsulate reading from streams and doing something with the data. Processors are generated by the Thrift compiler.

In Apache Thrift, Protocols and Transports can be mixed and matched. However,
our implementation does the mixing and matching for you and generates a
combination of (Protocol + Transport + Processor). This means that if you need
to support a new Protocol or Transport, you will need to integrate it into this
project.

Presently, we implement:

* Binary Protocol, Framed Client
* Binary Protocol, Framed Server

We are more than willing to accept contributions that add more!
