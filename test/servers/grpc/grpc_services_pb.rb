# Generated by the protocol buffer compiler.  DO NOT EDIT!
# Source: grpc.proto for package 'grpctest'

require 'grpc'
require 'grpc_pb'

module Grpctest
  module TestService
    class Service

      include GRPC::GenericService

      self.marshal_class_method = :encode
      self.unmarshal_class_method = :decode
      self.service_name = 'grpctest.TestService'

      # unary
      rpc :unary_1, Address, AddressId
      rpc :unary_2, AddressId, Address
      rpc :unary_cancel, NullMessage, NullMessage
      rpc :unary_unimplemented, NullMessage, NullMessage
      # client streaming
      rpc :client_stream, stream(Phone), NullMessage
      rpc :client_stream_cancel, stream(Phone), NullMessage
      rpc :client_stream_unimplemented, stream(Phone), NullMessage
      # server streaming
      rpc :server_stream, AddressId, stream(Phone)
      rpc :server_stream_cancel, NullMessage, stream(Phone)
      rpc :server_stream_unimplemented, NullMessage, stream(Phone)
      # bidi streaming
      rpc :bidi_stream, stream(Phone), stream(Phone)
      rpc :bidi_stream_cancel, stream(Phone), stream(Phone)
      rpc :bidi_stream_unimplemented, stream(Phone), stream(Phone)
    end

    Stub = Service.rpc_stub_class
  end
end