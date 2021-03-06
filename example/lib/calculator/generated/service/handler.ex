defmodule(Calculator.Generated.Service.Handler) do
  @moduledoc false
  (
    @callback add(left :: Thrift.i64(), right :: Thrift.i64()) :: Thrift.i64()
    @callback divide(left :: Thrift.i64(), right :: Thrift.i64()) :: Thrift.i64()
    @callback multiply(left :: Thrift.i64(), right :: Thrift.i64()) :: Thrift.i64()
    @callback subtract(left :: Thrift.i64(), right :: Thrift.i64()) :: Thrift.i64()
    @callback vector_product(
                left :: %Calculator.Generated.Vector{},
                right :: %Calculator.Generated.Vector{},
                type :: non_neg_integer
              ) :: %Calculator.Generated.VectorProductResult{}
  )
end
